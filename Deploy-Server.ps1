[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('Host')][string]$ServerHost,
    [string]$IPv6,
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')][string]$User = 'ubuntu',
    [Parameter(Mandatory)][string]$SshKey,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$Name,
    [ValidateRange(1, 65535)][int]$IngressPort = 443,
    [string]$PortHoppingRange,
    [string]$OutputPayloadPath,
    [string]$CredentialBundleDirectory,
    [switch]$RotateCredentials,
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

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Get-ManagedAuditExpectation {
    param([string]$Directory, [int]$Port, [string]$PortHoppingRange)
    if (-not $Directory) { return $null }
    $credentialPath = Join-Path $Directory 'credentials.json'
    $certificatePath = Join-Path $Directory 'server.crt'
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf) -or -not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { return $null }
    $credential = Read-RSTJson -Path $credentialPath -Label 'Managed route credentials'
    $auth = [string](Get-RSTOptional (Get-RSTOptional $credential 'hysteria') 'auth')
    $obfs = [string](Get-RSTOptional (Get-RSTOptional $credential 'hysteria') 'obfs')
    if (-not $auth -or -not $obfs) { throw 'Managed route credentials are incomplete.' }
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPemFile($certificatePath)
    try { $fingerprint = $certificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256).ToLowerInvariant() }
    finally { $certificate.Dispose() }
    $hop = if ([string]::IsNullOrWhiteSpace($PortHoppingRange)) { 'none' } else { $PortHoppingRange }
    $material = "hysteria2|port=$Port|hop=$hop|auth=$auth|obfs=$obfs|cert=$fingerprint"
    return [pscustomobject]@{ Fingerprint = $fingerprint; ConfigHash = Get-Sha256Hex -Value $material }
}

$ssh = Get-Command ssh -ErrorAction SilentlyContinue
$scp = Get-Command scp -ErrorAction SilentlyContinue
if (-not $ssh -or -not $scp) { throw 'OpenSSH client commands ssh and scp are required.' }
if (-not (Test-RSTIPv4 $ServerHost)) { throw 'ServerHost must be an IPv4 address.' }
if ($IPv6 -and -not (Test-RSTIPv6 $IPv6)) { throw 'IPv6 must be an IPv6 address.' }
$portHopping = ConvertTo-RSTPortHoppingRange -Value $PortHoppingRange -ListenPort $IngressPort
$PortHoppingRange = Get-RSTPortHoppingText -PortHopping $portHopping
if (-not $AuditOnly -and -not $OutputPayloadPath) { throw 'OutputPayloadPath is required for deployment.' }

$SshKey = (Resolve-Path -LiteralPath $SshKey).Path
if ($CredentialBundleDirectory) { $CredentialBundleDirectory = (Resolve-Path -LiteralPath $CredentialBundleDirectory).Path }
$auditExpectation = Get-ManagedAuditExpectation -Directory $CredentialBundleDirectory -Port $IngressPort -PortHoppingRange $PortHoppingRange
$serverDir = Join-Path $repoRoot 'server'
$remoteRoot = '/tmp/route-steward-' + ([Guid]::NewGuid().ToString('N'))
$target = $ServerHost
$transportCommon = @('-i', $SshKey, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=accept-new')
$sshCommon = $transportCommon + @('-l', $User)
$scpCommon = $transportCommon + @('-o', "User=$User")

Invoke-Native $ssh.Source ($sshCommon + @($target, 'true'))
try {
    Invoke-Native $ssh.Source ($sshCommon + @($target, "mkdir -m 700 $(ConvertTo-BashLiteral $remoteRoot)"))
    Invoke-Native $scp.Source ($scpCommon + @('-r', $serverDir, "${target}:${remoteRoot}/"))
    $remoteServer = "$remoteRoot/server"
    Invoke-Native $ssh.Source ($sshCommon + @($target, (ConvertTo-BashCommand @('sudo','bash',"$remoteServer/preflight.sh"))))

    if (-not $AuditOnly) {
        Invoke-Native $ssh.Source ($sshCommon + @($target, (ConvertTo-BashCommand @('sudo','bash',"$remoteServer/base-setup.sh","$remoteServer/config"))))
        Invoke-Native $ssh.Source ($sshCommon + @($target, (ConvertTo-BashCommand @('sudo','bash',"$remoteServer/install-path-components.sh","$remoteServer/config"))))

        $remoteCredentialDirectory = $null
        if ($CredentialBundleDirectory) {
            $remoteCredentialDirectory = "$remoteRoot/managed-credential"
            Invoke-Native $scp.Source ($scpCommon + @('-r', $CredentialBundleDirectory, "${target}:${remoteCredentialDirectory}"))
        }

        $configure = @('sudo','bash',"$remoteServer/configure-ingress.sh",'--ipv4',$ServerHost,'--name',$Name,'--port',[string]$IngressPort,'--output','/var/lib/route-steward/client-payload.yaml')
        if ($PortHoppingRange) { $configure += @('--port-hopping-range',$PortHoppingRange) }
        if ($IPv6) { $configure += @('--ipv6',$IPv6) }
        if ($remoteCredentialDirectory) { $configure += @('--credential-dir',$remoteCredentialDirectory) }
        if ($RotateCredentials) { $configure += '--rotate' }
        Invoke-Native $ssh.Source ($sshCommon + @($target, (ConvertTo-BashCommand $configure)))

        $localPayload = [IO.Path]::GetFullPath($OutputPayloadPath)
        $privateDir = Split-Path -Parent $localPayload
        New-Item -ItemType Directory -Force -Path $privateDir | Out-Null
        Protect-RSTPath -Path $privateDir -Directory
        $remoteExport = "$remoteRoot/client-payload.yaml"
        $copyCommand = ConvertTo-BashCommand @('sudo','install','-m','0600','-o',$User,'/var/lib/route-steward/client-payload.yaml',$remoteExport)
        Invoke-Native $ssh.Source ($sshCommon + @($target, $copyCommand))
        Invoke-Native $scp.Source ($scpCommon + @("${target}:${remoteExport}", $localPayload))
        Protect-RSTPath -Path $localPayload
    }

    $audit = @('sudo','bash',"$remoteServer/audit.sh",'--ingress-port',[string]$IngressPort)
    if ($PortHoppingRange) { $audit += @('--port-hopping-range',$PortHoppingRange) }
    if ($auditExpectation) {
        $audit += @('--expected-fingerprint',[string]$auditExpectation.Fingerprint,'--expected-config-hash',[string]$auditExpectation.ConfigHash)
    }
    $auditOutput = @(& $ssh.Source @($sshCommon + @($target, (ConvertTo-BashCommand $audit))) 2>&1 | ForEach-Object { [string]$_ })
    $auditExit = $LASTEXITCODE
    $category = @($auditOutput | Where-Object { $_ -match '^RST_AUDIT_CATEGORY=' } | Select-Object -Last 1)
    if (-not $category.Count) { $auditOutput += 'RST_AUDIT_CATEGORY=undetermined' }
    foreach ($line in $auditOutput) {
        if ($line -match '^(?:RST_AUDIT_CATEGORY|IPV4|HYSTERIA_VERSION|WIREGUARD_VERSION|AUDIT_OK)=') { Write-Output $line }
    }
    Write-Output "RST_AUDIT_EXIT_CODE=$auditExit"
    if (-not $AuditOnly -and $auditExit -ne 0) { throw 'Post-deploy route audit found drift.' }
}
finally {
    & $ssh.Source @sshCommon $target "rm -rf $(ConvertTo-BashLiteral $remoteRoot)" 2>$null | Out-Null
}
