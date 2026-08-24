[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EntryHost,
    [string]$EntryIPv6,
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')][string]$EntryUser = 'ubuntu',
    [Parameter(Mandatory)][string]$EntrySshKey,
    [Parameter(Mandatory)][string]$ExitHost,
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')][string]$ExitUser = 'ubuntu',
    [Parameter(Mandatory)][string]$ExitSshKey,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Name,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$ViaName,
    [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$IngressPort,
    [string]$PortHoppingRange,
    [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$TunnelPort,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9_-]{0,14}$')][string]$Interface,
    [Parameter(Mandatory)][string]$TunnelSubnet,
    [Parameter(Mandatory)][string]$EntryTunnelAddress,
    [Parameter(Mandatory)][string]$ExitTunnelAddress,
    [string]$CredentialBundleDirectory,
    [string]$LinkSecretPath,
    [string]$OutputPayloadPath,
    [switch]$AuditOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = $PSScriptRoot
. (Join-Path $repoRoot 'lib\RouteSteward.Core.ps1')

function Invoke-Native {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) { throw "$FilePath exited with code $LASTEXITCODE." }
}

function Invoke-NativeCapture {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string[]]$ArgumentList)
    $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw "$FilePath exited with code $LASTEXITCODE." }
    return $output
}

function ConvertTo-BashLiteral {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $quote = [string][char]39
    $replacement = $quote + [char]34 + $quote + [char]34 + $quote
    return $quote + $Value.Replace($quote, $replacement) + $quote
}

function ConvertTo-BashCommand {
    param([Parameter(Mandatory)][string[]]$Token)
    return ($Token | ForEach-Object { ConvertTo-BashLiteral $_ }) -join ' '
}

function Get-PublicKey {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Output)
    $line = $Output | Where-Object { $_ -match '^PUBLIC_KEY=(?<key>[A-Za-z0-9+/]{43}=)$' } | Select-Object -Last 1
    if (-not $line) { throw 'WireGuard public key was not returned.' }
    return ([regex]::Match($line, '^PUBLIC_KEY=(?<key>.+)$')).Groups['key'].Value
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Get-ManagedRelayAuditExpectation {
    param([string]$Directory, [int]$Port, [string]$BindInterface, [string]$PortHoppingRange)
    if (-not $Directory) { return $null }
    $credentialPath = Join-Path $Directory 'credentials.json'
    $certificatePath = Join-Path $Directory 'server.crt'
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf) -or -not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { return $null }
    $credential = Read-RSTJson -Path $credentialPath -Label 'Managed relay credentials'
    $auth = [string](Get-RSTOptional (Get-RSTOptional $credential 'hysteria') 'auth')
    $obfs = [string](Get-RSTOptional (Get-RSTOptional $credential 'hysteria') 'obfs')
    if (-not $auth -or -not $obfs) { throw 'Managed relay credentials are incomplete.' }
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certificatePath)
    try { $fingerprint = $certificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256).ToLowerInvariant() }
    finally { $certificate.Dispose() }
    $hop = if ([string]::IsNullOrWhiteSpace($PortHoppingRange)) { 'none' } else { $PortHoppingRange }
    $material = "hysteria2-relay|port=$Port|hop=$hop|auth=$auth|obfs=$obfs|cert=$fingerprint|bind=$BindInterface"
    return [pscustomobject]@{ Fingerprint = $fingerprint; ConfigHash = Get-Sha256Hex -Value $material }
}

function Write-SanitizedAuditOutput {
    param([Parameter(Mandatory)][string[]]$Output, [Parameter(Mandatory)][int]$ExitCode)
    $hasCategory = @($Output | Where-Object { $_ -match '^RST_AUDIT_CATEGORY=' }).Count -gt 0
    if (-not $hasCategory) { $Output += 'RST_AUDIT_CATEGORY=undetermined' }
    foreach ($line in $Output) {
        if ($line -match '^(?:RST_AUDIT_CATEGORY|RELAY_EGRESS_IPV4|HYSTERIA_VERSION|WIREGUARD_VERSION|RELAY_(?:ENTRY|EXIT)_AUDIT_OK|RELAY_EGRESS_OK)=') { Write-Output $line }
    }
    Write-Output "RST_AUDIT_EXIT_CODE=$ExitCode"
}

$ssh = Get-Command ssh -ErrorAction SilentlyContinue
$scp = Get-Command scp -ErrorAction SilentlyContinue
if (-not $ssh -or -not $scp) { throw 'OpenSSH client commands ssh and scp are required.' }
if (-not (Test-RSTIPv4 $EntryHost)) { throw 'EntryHost must be an IPv4 address.' }
if (-not (Test-RSTIPv4 $ExitHost)) { throw 'ExitHost must be an IPv4 address.' }
if ($EntryHost -eq $ExitHost) { throw 'Relay entry and exit must be different servers.' }
if ($EntryIPv6 -and -not (Test-RSTIPv6 $EntryIPv6)) { throw 'EntryIPv6 must be an IPv6 address.' }
$portHopping = ConvertTo-RSTPortHoppingRange -Value $PortHoppingRange -ListenPort $IngressPort
$PortHoppingRange = Get-RSTPortHoppingText -PortHopping $portHopping
if ($TunnelSubnet -notmatch '^10\.77\.(?:[0-9]|[1-9][0-9]|[12][0-9]{2})\.0/30$') { throw 'TunnelSubnet must use the supported 10.77.x.0/30 allocation.' }
$entryPeerIp = ($EntryTunnelAddress -split '/', 2)[0]
$exitPeerIp = ($ExitTunnelAddress -split '/', 2)[0]
if (-not (Test-RSTIPv4 $entryPeerIp) -or -not (Test-RSTIPv4 $exitPeerIp)) { throw 'Tunnel endpoint addresses are invalid.' }
if (-not $AuditOnly -and -not $OutputPayloadPath) { throw 'OutputPayloadPath is required for deployment.' }

$EntrySshKey = (Resolve-Path -LiteralPath $EntrySshKey).Path
$ExitSshKey = (Resolve-Path -LiteralPath $ExitSshKey).Path
if ($CredentialBundleDirectory) { $CredentialBundleDirectory = (Resolve-Path -LiteralPath $CredentialBundleDirectory).Path }
$auditExpectation = Get-ManagedRelayAuditExpectation -Directory $CredentialBundleDirectory -Port $IngressPort -BindInterface $Interface -PortHoppingRange $PortHoppingRange

$localSecretStage = $null
$linkSecret = $null
if ($LinkSecretPath) {
    $LinkSecretPath = (Resolve-Path -LiteralPath $LinkSecretPath).Path
    try { $linkSecret = [IO.File]::ReadAllText($LinkSecretPath, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { throw 'The managed Link secret is not valid JSON.' }
    foreach ($side in 'entry','exit') {
        $privateKey = [string]$linkSecret.$side.private_key
        $publicKey = [string]$linkSecret.$side.public_key
        if ($privateKey -notmatch '^[A-Za-z0-9+/]{43}=$' -or $publicKey -notmatch '^[A-Za-z0-9+/]{43}=$') { throw "The managed Link $side key pair is invalid." }
    }
    if (-not $AuditOnly) {
        $localSecretStage = Join-Path ([IO.Path]::GetTempPath()) ('rst-link-secret-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $localSecretStage | Out-Null
        Protect-RSTPath -Path $localSecretStage -Directory
        foreach ($side in 'entry','exit') {
            $path = Join-Path $localSecretStage "$side.key"
            [IO.File]::WriteAllText($path, ([string]$linkSecret.$side.private_key) + "`n", [Text.UTF8Encoding]::new($false))
            Protect-RSTPath -Path $path
        }
    }
}

$serverDir = Join-Path $repoRoot 'server'
$entryTarget = $EntryHost
$exitTarget = $ExitHost
$entryRoot = '/tmp/route-steward-relay-entry-' + [Guid]::NewGuid().ToString('N')
$exitRoot = '/tmp/route-steward-relay-exit-' + [Guid]::NewGuid().ToString('N')
$entryTransport = @('-i', $EntrySshKey, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=accept-new')
$exitTransport = @('-i', $ExitSshKey, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=accept-new')
$entrySsh = $entryTransport + @('-l', $EntryUser)
$exitSsh = $exitTransport + @('-l', $ExitUser)
$entryScp = $entryTransport + @('-o', "User=$EntryUser")
$exitScp = $exitTransport + @('-o', "User=$ExitUser")

Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, 'true'))
Invoke-Native $ssh.Source ($exitSsh + @($exitTarget, 'true'))
try {
    Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, "mkdir -m 700 $(ConvertTo-BashLiteral $entryRoot)"))
    Invoke-Native $ssh.Source ($exitSsh + @($exitTarget, "mkdir -m 700 $(ConvertTo-BashLiteral $exitRoot)"))
    Invoke-Native $scp.Source ($entryScp + @('-r', $serverDir, "${entryTarget}:${entryRoot}/"))
    Invoke-Native $scp.Source ($exitScp + @('-r', $serverDir, "${exitTarget}:${exitRoot}/"))
    $entryServer = "$entryRoot/server"
    $exitServer = "$exitRoot/server"

    Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, (ConvertTo-BashCommand @('sudo','bash',"$entryServer/preflight.sh"))))
    Invoke-Native $ssh.Source ($exitSsh + @($exitTarget, (ConvertTo-BashCommand @('sudo','bash',"$exitServer/preflight.sh"))))

    if (-not $AuditOnly) {
        Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, (ConvertTo-BashCommand @('sudo','bash',"$entryServer/base-setup.sh","$entryServer/config"))))
        Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, (ConvertTo-BashCommand @('sudo','bash',"$entryServer/install-path-components.sh","$entryServer/config"))))
        Invoke-Native $ssh.Source ($exitSsh + @($exitTarget, (ConvertTo-BashCommand @('sudo','bash',"$exitServer/base-setup.sh","$exitServer/config"))))

        $remoteCredentialDirectory = $null
        if ($CredentialBundleDirectory) {
            $remoteCredentialDirectory = "$entryRoot/managed-credential"
            Invoke-Native $scp.Source ($entryScp + @('-r', $CredentialBundleDirectory, "${entryTarget}:${remoteCredentialDirectory}"))
        }

        $entryPrepare = @('sudo','bash',"$entryServer/prepare-relay.sh",'--interface',$Interface)
        $exitPrepare = @('sudo','bash',"$exitServer/prepare-relay.sh",'--interface',$Interface)
        if ($localSecretStage) {
            Invoke-Native $scp.Source ($entryScp + @((Join-Path $localSecretStage 'entry.key'), "${entryTarget}:${entryRoot}/managed-link.key"))
            Invoke-Native $scp.Source ($exitScp + @((Join-Path $localSecretStage 'exit.key'), "${exitTarget}:${exitRoot}/managed-link.key"))
            $entryPrepare += @('--private-key-file',"$entryRoot/managed-link.key")
            $exitPrepare += @('--private-key-file',"$exitRoot/managed-link.key")
        }
        $entryPublicKey = Get-PublicKey -Output (Invoke-NativeCapture $ssh.Source ($entrySsh + @($entryTarget, (ConvertTo-BashCommand $entryPrepare))))
        $exitPublicKey = Get-PublicKey -Output (Invoke-NativeCapture $ssh.Source ($exitSsh + @($exitTarget, (ConvertTo-BashCommand $exitPrepare))))

        $exitConfigure = @('sudo','bash',"$exitServer/configure-relay-exit.sh",'--interface',$Interface,'--listen-port',[string]$TunnelPort,'--subnet',$TunnelSubnet,'--local-cidr',$ExitTunnelAddress,'--peer-ip',$entryPeerIp,'--peer-public-key',$entryPublicKey,'--entry-public-ip',$EntryHost)
        Invoke-Native $ssh.Source ($exitSsh + @($exitTarget, (ConvertTo-BashCommand $exitConfigure)))

        $entryConfigure = @('sudo','bash',"$entryServer/configure-relay-entry.sh",'--interface',$Interface,'--local-cidr',$EntryTunnelAddress,'--peer-ip',$exitPeerIp,'--peer-public-key',$exitPublicKey,'--exit-endpoint',$ExitHost,'--tunnel-port',[string]$TunnelPort,'--ingress-port',[string]$IngressPort,'--entry-ipv4',$EntryHost,'--exit-ipv4',$ExitHost,'--name',$Name,'--via-name',$ViaName,'--output','/var/lib/route-steward/relay-client-payload.yaml','--unit-dir',"$entryServer/config")
        if ($PortHoppingRange) { $entryConfigure += @('--port-hopping-range',$PortHoppingRange) }
        if ($EntryIPv6) { $entryConfigure += @('--entry-ipv6',$EntryIPv6) }
        if ($remoteCredentialDirectory) { $entryConfigure += @('--credential-dir',$remoteCredentialDirectory) }
        Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, (ConvertTo-BashCommand $entryConfigure)))

        $localPayload = [IO.Path]::GetFullPath($OutputPayloadPath)
        $privateDir = Split-Path -Parent $localPayload
        New-Item -ItemType Directory -Force -Path $privateDir | Out-Null
        Protect-RSTPath -Path $privateDir -Directory
        $remoteExport = "$entryRoot/relay-client-payload.yaml"
        $copyCommand = ConvertTo-BashCommand @('sudo','install','-m','0600','-o',$EntryUser,'/var/lib/route-steward/relay-client-payload.yaml',$remoteExport)
        Invoke-Native $ssh.Source ($entrySsh + @($entryTarget, $copyCommand))
        Invoke-Native $scp.Source ($entryScp + @("${entryTarget}:${remoteExport}", $localPayload))
        Protect-RSTPath -Path $localPayload
    }

    $exitAudit = @('sudo','bash',"$exitServer/audit-relay.sh",'--role','exit','--interface',$Interface,'--tunnel-port',[string]$TunnelPort,'--subnet',$TunnelSubnet,'--peer-ip',$entryPeerIp)
    if ($linkSecret) { $exitAudit += @('--expected-peer-public-key',[string]$linkSecret.entry.public_key) }
    $exitOutput = @(& $ssh.Source @($exitSsh + @($exitTarget, (ConvertTo-BashCommand $exitAudit))) 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-SanitizedAuditOutput -Output $exitOutput -ExitCode $exitCode
        if (-not $AuditOnly) { throw 'Post-deploy relay exit audit found drift.' }
        return
    }

    $entryAudit = @('sudo','bash',"$entryServer/audit-relay.sh",'--role','entry','--interface',$Interface,'--name',$Name,'--ingress-port',[string]$IngressPort,'--peer-ip',$exitPeerIp,'--expected-exit',$ExitHost)
    if ($PortHoppingRange) { $entryAudit += @('--port-hopping-range',$PortHoppingRange) }
    if ($linkSecret) { $entryAudit += @('--expected-peer-public-key',[string]$linkSecret.exit.public_key) }
    if ($auditExpectation) { $entryAudit += @('--expected-fingerprint',[string]$auditExpectation.Fingerprint,'--expected-config-hash',[string]$auditExpectation.ConfigHash) }
    $entryOutput = @(& $ssh.Source @($entrySsh + @($entryTarget, (ConvertTo-BashCommand $entryAudit))) 2>&1 | ForEach-Object { [string]$_ })
    $entryCode = $LASTEXITCODE
    Write-SanitizedAuditOutput -Output $entryOutput -ExitCode $entryCode
    if (-not $AuditOnly -and $entryCode -ne 0) { throw 'Post-deploy relay entry audit found drift.' }
}
finally {
    & $ssh.Source @entrySsh $entryTarget "rm -rf $(ConvertTo-BashLiteral $entryRoot)" 2>$null | Out-Null
    & $ssh.Source @exitSsh $exitTarget "rm -rf $(ConvertTo-BashLiteral $exitRoot)" 2>$null | Out-Null
    if ($localSecretStage -and (Test-Path -LiteralPath $localSecretStage)) {
        $resolvedStage = [IO.Path]::GetFullPath($localSecretStage)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
    }
}
