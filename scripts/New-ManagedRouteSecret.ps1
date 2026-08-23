[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,62}$')][string]$RouteId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$DisplayName,
    [Parameter(Mandatory)][string]$EntryIPv4,
    [string]$EntryIPv6,
    [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
    [Parameter(Mandatory)][string]$SecretDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
if (-not (Test-RSTIPv4 $EntryIPv4)) { throw 'EntryIPv4 is invalid.' }
if ($EntryIPv6 -and -not (Test-RSTIPv6 $EntryIPv6)) { throw 'EntryIPv6 is invalid.' }

$SecretDirectory = [IO.Path]::GetFullPath($SecretDirectory)
if (Test-Path -LiteralPath $SecretDirectory) { throw "Managed secret directory for '$RouteId' already exists." }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-managed-secret-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    Protect-RSTPath -Path $stage -Directory
    $authBytes = New-Object byte[] 32
    $obfsBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($authBytes)
    [Security.Cryptography.RandomNumberGenerator]::Fill($obfsBytes)
    $auth = [Convert]::ToHexString($authBytes).ToLowerInvariant()
    $obfs = [Convert]::ToHexString($obfsBytes).ToLowerInvariant()

    $ecdsa = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve+NamedCurves]::nistP256)
    try {
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$EntryIPv4", $ecdsa, [Security.Cryptography.HashAlgorithmName]::SHA256)
        $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
        $parsedV4 = $null
        [void][Net.IPAddress]::TryParse($EntryIPv4, [ref]$parsedV4)
        $san.AddIpAddress($parsedV4)
        if ($EntryIPv6) {
            $parsedV6 = $null
            [void][Net.IPAddress]::TryParse($EntryIPv6, [ref]$parsedV6)
            $san.AddIpAddress($parsedV6)
        }
        $request.CertificateExtensions.Add($san.Build())
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
        $eku = [Security.Cryptography.OidCollection]::new()
        [void]$eku.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($eku, $false))
        $certificate = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-5), [DateTimeOffset]::UtcNow.AddYears(10))
        try {
            $certificatePem = $certificate.ExportCertificatePem()
            $privateKeyPem = $ecdsa.ExportPkcs8PrivateKeyPem()
            $fingerprint = ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData($certificate.RawData)) -replace '-', '').ToLowerInvariant()
        }
        finally { $certificate.Dispose() }
    }
    finally { $ecdsa.Dispose() }

    $credential = [ordered]@{ schema = 1; hysteria = [ordered]@{ auth = $auth; obfs = $obfs }; created_at = [DateTime]::UtcNow.ToString('o'); certificate_not_after = [DateTimeOffset]::UtcNow.AddYears(10).ToString('o') }
    [IO.File]::WriteAllText((Join-Path $stage 'credentials.json'), ($credential | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage 'server.crt'), $certificatePem, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $stage 'server.key'), $privateKeyPem, [Text.UTF8Encoding]::new($false))

    function Write-Node([string]$Suffix, [string]$Address) {
        return @"
  - name: $DisplayName-HY2-$Suffix
    type: hysteria2
    server: '$Address'
    port: $Port
    password: '$auth'
    sni: '$EntryIPv4'
    skip-cert-verify: true
    fingerprint: '$fingerprint'
    alpn: [h3]
    obfs: salamander
    obfs-password: '$obfs'
"@
    }
    $nodes = [Collections.Generic.List[string]]::new()
    if ($EntryIPv6) { $nodes.Add((Write-Node -Suffix 'v6' -Address $EntryIPv6)) }
    $nodes.Add((Write-Node -Suffix 'v4' -Address $EntryIPv4))
    $payload = "schema: 1`nname: '$DisplayName'`nproxies:`n" + (($nodes | ForEach-Object { $_.TrimEnd() }) -join "`n") + "`n"
    [IO.File]::WriteAllText((Join-Path $stage 'client-payload.yaml'), $payload, [Text.UTF8Encoding]::new($false))
    Get-ChildItem -LiteralPath $stage -File | ForEach-Object { Protect-RSTPath -Path $_.FullName }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SecretDirectory) | Out-Null
    Move-Item -LiteralPath $stage -Destination $SecretDirectory
    Protect-RSTPath -Path $SecretDirectory -Directory
}
finally {
    if (Test-Path -LiteralPath $stage) {
        $resolved = [IO.Path]::GetFullPath($stage)
        if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
}
