[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$version = [IO.File]::ReadAllText((Join-Path $repo 'version.txt'), [Text.Encoding]::UTF8).Trim()
if ($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'version.txt is not plain SemVer X.Y.Z.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ppm-version-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    foreach ($case in @(
        @{ Current = '0.1.9'; Type = 'patch'; Expected = '0.1.10' },
        @{ Current = '0.1.9'; Type = 'minor'; Expected = '0.2.0' },
        @{ Current = '0.9.9'; Type = 'major'; Expected = '1.0.0' }
    )) {
        $path = Join-Path $tempRoot ($case.Type + '.txt')
        [IO.File]::WriteAllText($path, ($case.Current + "`n"), [Text.UTF8Encoding]::new($false))
        $reported = (& (Join-Path $repo 'scripts\Bump-Version.ps1') -Type $case.Type -VersionFile $path | Out-String).Trim()
        $stored = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Trim()
        Assert-Equal $reported $case.Expected "Reported $($case.Type) version is wrong."
        Assert-Equal $stored $case.Expected "Stored $($case.Type) version is wrong."
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$capabilitiesRaw = & (Join-Path $repo 'agent\ppm-agent.ps1') capabilities 2>&1
$capabilities = ($capabilitiesRaw | Out-String).Trim() | ConvertFrom-Json
if (-not $capabilities.success) { throw 'Agent capability discovery failed.' }
Assert-Equal ([string]$capabilities.data.drivers.product_version) $version 'Agent product version does not match version.txt.'

Write-Host "Product version behavior passed for Private Proxy Manager $version."
