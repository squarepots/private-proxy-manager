$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:PPMRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Get-PPMProductVersion {
    $path = Join-Path $script:PPMRepositoryRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Canonical PPM version.txt is missing.' }
    $version = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
        throw 'Canonical PPM product version is not valid SemVer.'
    }
    return $version
}
