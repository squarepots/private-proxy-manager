[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$PayloadPath,

    [string]$MihomoPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
    finally { $listener.Stop() }
}

function Wait-Controller {
    param([Parameter(Mandatory)][string]$Controller, [Parameter(Mandatory)][hashtable]$Headers)
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            Invoke-RestMethod -Uri "$Controller/version" -Headers $Headers -TimeoutSec 1 | Out-Null
            return $true
        }
        catch { Start-Sleep -Milliseconds 500 }
    }
    return $false
}

$nodeBodies = [Collections.Generic.List[string]]::new()
$expectedExit = @{}
foreach ($path in $PayloadPath) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    $payload = [IO.File]::ReadAllText($resolved, [Text.Encoding]::UTF8)
    if ($payload -notmatch '(?m)^ipv4:\s*["'']?(?<ip>[0-9.]+)') { throw 'A payload does not declare its fixed IPv4 exit.' }
    $ipv4 = $Matches.ip
    if ($payload -notmatch '(?ms)^proxies:\s*\r?\n(?<nodes>.+)\z') { throw 'A payload proxy block is missing.' }
    $nodeBody = $Matches.nodes.TrimEnd()
    $names = @([regex]::Matches($nodeBody, '(?m)^\s{2}- name:\s*["'']?(?<name>[^"''\r\n]+)["'']?\s*$') | ForEach-Object { $_.Groups['name'].Value.Trim() })
    if ($names.Count -ne 2) { throw 'Each route payload must contain two Hysteria2 nodes.' }
    foreach ($name in $names) {
        if ($expectedExit.ContainsKey($name)) { throw "Duplicate node name '$name'." }
        $expectedExit[$name] = $ipv4
    }
    $nodeBodies.Add($nodeBody)
}
$nodeNames = @($expectedExit.Keys | Sort-Object)

if (-not $MihomoPath) {
    $MihomoPath = @(
        (Join-Path $env:ProgramFiles 'Clash Verge\verge-mihomo.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Clash Verge\verge-mihomo.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $MihomoPath) { throw 'verge-mihomo.exe was not found.' }
$MihomoPath = (Resolve-Path -LiteralPath $MihomoPath).Path

$mixedPort = Get-FreeTcpPort
$controllerPort = Get-FreeTcpPort
$controller = "http://127.0.0.1:$controllerPort"
$secret = [Guid]::NewGuid().ToString('N')
$headers = @{ Authorization = "Bearer $secret" }
$groupName = 'RST-ROUTE-ISOLATED-TEST'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-route-network-' + [Guid]::NewGuid().ToString('N'))
$core = $null

try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $configLines = @(
        "mixed-port: $mixedPort",
        "external-controller: 127.0.0.1:$controllerPort",
        "secret: '$secret'",
        'mode: rule',
        'log-level: debug',
        'ipv6: true',
        'proxies:',
        ($nodeBodies -join "`n"),
        'proxy-groups:',
        "  - name: $groupName",
        '    type: select',
        '    proxies:'
    )
    foreach ($node in $nodeNames) { $configLines += "      - '$($node.Replace("'", "''"))'" }
    $configLines += @('rules:', "  - MATCH,$groupName", '')
    $configPath = Join-Path $stage 'config.yaml'
    $stdoutPath = Join-Path $stage 'mihomo.stdout.log'
    $stderrPath = Join-Path $stage 'mihomo.stderr.log'
    [IO.File]::WriteAllLines($configPath, $configLines, [Text.UTF8Encoding]::new($false))
    $validation = @(& $MihomoPath -t -d $stage -f $configPath 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) {
        $safeValidation = ($validation -join ' ') `
            -replace '(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])', '[address]' `
            -replace '(?i)\b[0-9a-f]{32,}\b', '[secret]' `
            -replace '\b[0-9a-f]{8}-[0-9a-f-]{27,}\b', '[uuid]'
        throw "The isolated Mihomo configuration was rejected: $safeValidation"
    }
    $core = Start-Process -FilePath $MihomoPath -ArgumentList @('-d', $stage, '-f', $configPath) -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if (-not (Wait-Controller -Controller $controller -Headers $headers)) {
        $state = if ($core.HasExited) { "process exited with code $($core.ExitCode)" } else { 'process stayed active but its controller was unavailable' }
        throw "The isolated Mihomo test core did not start: $state."
    }

    $groupUri = "$controller/proxies/$([Uri]::EscapeDataString($groupName))"
    $proxyUri = "http://127.0.0.1:$mixedPort"
    foreach ($node in $nodeNames) {
        $body = @{ name = $node } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Put -Uri $groupUri -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 5 | Out-Null
        $confirmed = $false
        $elapsed = 0
        $lastFailure = $null
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            try {
                $responsePath = Join-Path $stage ('exit-' + [Guid]::NewGuid().ToString('N') + '.txt')
                & curl.exe --silent --show-error --fail --no-keepalive --proxy $proxyUri --connect-timeout 10 --max-time 30 `
                    --output $responsePath https://api.ipify.org 2>$null
                if ($LASTEXITCODE -ne 0) { throw 'The proxy request did not complete.' }
                $exit = ([IO.File]::ReadAllText($responsePath, [Text.Encoding]::ASCII)).Trim()
                Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
                $stopwatch.Stop()
                if ($exit -ne $expectedExit[$node]) { throw "$node used an unexpected exit address." }
                $elapsed = $stopwatch.ElapsedMilliseconds
                $confirmed = $true
                break
            }
            catch {
                $stopwatch.Stop()
                if ($_.Exception.Message -match 'unexpected exit address') { throw }
                $lastFailure = $_
                if ($attempt -lt 3) { Start-Sleep -Seconds 1 }
            }
        }
        if (-not $confirmed) { throw "$node did not complete the fixed-exit check after 3 attempts: $($lastFailure.Exception.Message)" }
        Write-Host ("OK {0}: {1} ms request, fixed IPv4 exit confirmed" -f $node, $elapsed)
    }
}
catch {
    $logPaths = @($stdoutPath, $stderrPath)
    $diagnostic = @($logPaths | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Content -LiteralPath $_ -Tail 40 }) -join "`n"
    if ($diagnostic) {
        $safeDiagnostic = $diagnostic `
            -replace '(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?::[0-9]+)?(?![0-9])', '[address]' `
            -replace '(?i)\b[0-9a-f]{32,}\b', '[secret]' `
            -replace '\b[0-9a-f]{8}-[0-9a-f-]{27,}\b', '[uuid]' `
            -replace '\b[A-Za-z0-9+/]{40,}={0,2}\b', '[key]'
        Write-Warning $safeDiagnostic
    }
    throw
}
finally {
    if ($core -and -not $core.HasExited) { Stop-Process -Id $core.Id -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ("All {0} nodes passed the isolated live test; active Clash state was not changed." -f $nodeNames.Count)
