$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:RSTRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Get-RSTProductVersion {
    $path = Join-Path $script:RSTRepositoryRoot 'version.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Canonical RST version.txt is missing.' }
    $version = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
        throw 'Canonical RST product version is not valid SemVer.'
    }
    return $version
}
