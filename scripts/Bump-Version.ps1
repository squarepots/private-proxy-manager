[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Type,

    [string]$VersionFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'version.txt')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$path = [IO.Path]::GetFullPath($VersionFile)
if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Version file does not exist: $path"
}

$current = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Trim()
$match = [regex]::Match($current, '^(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)$')
if (-not $match.Success) {
    throw "Version must be plain SemVer X.Y.Z: $current"
}

$major = [int]$match.Groups['major'].Value
$minor = [int]$match.Groups['minor'].Value
$patch = [int]$match.Groups['patch'].Value

switch ($Type) {
    'patch' { $patch++ }
    'minor' { $minor++; $patch = 0 }
    'major' { $major++; $minor = 0; $patch = 0 }
}

$next = "$major.$minor.$patch"
[IO.File]::WriteAllText($path, "$next`n", [Text.UTF8Encoding]::new($false))
Write-Output $next
