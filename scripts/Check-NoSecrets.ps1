[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Test-AllowedIPv4Literal {
    param([Parameter(Mandatory)][string]$Value)
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$address) -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { return $true }
    $b = $address.GetAddressBytes()
    if ($Value -in @('0.0.0.0','10.0.0.0','100.64.0.0','127.0.0.0','169.254.0.0','172.16.0.0','192.168.0.0','224.0.0.0','240.0.0.0')) { return $true }
    if ($b[0] -eq 127 -or ($b[0] -eq 10 -and $b[1] -eq 77)) { return $true }
    if ($b[0] -eq 192 -and $b[1] -eq 0 -and $b[2] -eq 2) { return $true }
    if ($b[0] -eq 198 -and $b[1] -in @(18,19)) { return $true }
    if ($b[0] -eq 198 -and $b[1] -eq 51 -and $b[2] -eq 100) { return $true }
    if ($b[0] -eq 203 -and $b[1] -eq 0 -and $b[2] -eq 113) { return $true }
    if ($Value -in @('1.1.1.1','8.8.8.8','223.5.5.5','1.12.12.12')) { return $true }
    return $false
}

function Test-AllowedIPv6Literal {
    param([Parameter(Mandatory)][string]$Value)
    $address = $null
    if (-not [Net.IPAddress]::TryParse($Value, [ref]$address) -or $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetworkV6) { return $true }
    if ($address.Equals([Net.IPAddress]::IPv6Any) -or $address.Equals([Net.IPAddress]::IPv6Loopback)) { return $true }
    if ($Value -in @('fc00::','fe80::','ff00::')) { return $true }
    $b = $address.GetAddressBytes()
    if ($b[0] -eq 0x20 -and $b[1] -eq 0x01 -and $b[2] -eq 0x0D -and $b[3] -eq 0xB8) { return $true }
    return $false
}

$files = & git -C $repo ls-files --cached --others --exclude-standard
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
$violations = [Collections.Generic.List[string]]::new()

foreach ($relative in $files) {
    $normalized = $relative.Replace('\', '/')
    if ($normalized -match '(^|/)(private|exports|delivery|secrets)(/|$)' -or
        $normalized -match '(?i)((?:^|/)(?:payload|client)(?:[-_.][^/]*)?\.ya?ml$|(?:^|/)[^/]+-(?:nodes|import|subscription)\.(?:txt|html)$|inventory\.json$|observed\.json$|client-render-manifest\.json$|RECOVERY-METADATA\.json$|SHA256SUMS$|\.zip$|\.7z$|\.pem$|\.pfx$|\.p12$|\.key$)') {
        $violations.Add("forbidden generated/secret path: $relative")
        continue
    }
    $path = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    if ([IO.Path]::GetExtension($path) -ieq '.png') { continue }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    foreach ($rule in @(
        @{ Name = 'private key material'; Pattern = '-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----' },
        @{ Name = 'AWS access key'; Pattern = '(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])' },
        @{ Name = 'GitHub token'; Pattern = '(?<![A-Za-z0-9])(?:ghp|github_pat)_[A-Za-z0-9_]{20,}' },
        @{ Name = 'Slack token'; Pattern = '(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{20,}' },
        @{ Name = 'embedded subscription credential'; Pattern = '(?i)https?://[^\s"'']+[?&](?:token|sub|subscription)=[^&\s"'']{8,}' },
        @{ Name = 'private Worker subscription bearer'; Pattern = '(?i)https?://[^\s"'']+\.workers\.dev/s/[A-Za-z0-9_-]{20,}' }
        @{ Name = 'absolute user home path'; Pattern = '(?i)(?:[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\r\n]+[\\/]|/(?:Users|home)/[^/\r\n]+/)' }
    )) {
        if ($text -match $rule.Pattern) { $violations.Add("$($rule.Name): $relative") }
    }

    foreach ($match in [regex]::Matches($text, '(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])')) {
        $literal = $match.Value
        if (-not (Test-AllowedIPv4Literal -Value $literal)) { $violations.Add("unexpected IPv4 literal '$literal': $relative") }
    }
    foreach ($match in [regex]::Matches($text, '(?i)(?<![0-9a-z_:])(?:[0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}(?![0-9a-z_:])')) {
        $literal = $match.Value
        if ($literal -notmatch '[0-9a-f]') { continue }
        if (-not (Test-AllowedIPv6Literal -Value $literal)) { $violations.Add("unexpected IPv6 literal '$literal': $relative") }
    }
}

if ($violations.Count) {
    $violations | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "Secret/path/public-address scan passed for $($files.Count) files."
