[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArchivePath,
    [Parameter(Mandatory)][string]$DestinationPrivateDirectory,
    [string]$SevenZipPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')
. (Join-Path $repo 'lib\RouteSteward.Recovery.ps1')

function Resolve-SevenZip {
    param([string]$Requested)
    if ($Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
    foreach ($name in '7z','7zz','7z.exe') {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    if ($env:OS -eq 'Windows_NT') {
        foreach ($candidate in @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path $env:ProgramFiles 'NanaZip\7z.exe'))) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return [IO.Path]::GetFullPath($candidate) }
        }
    }
    throw '7-Zip (7z/7zz) was not found.'
}

$archive = (Resolve-Path -LiteralPath $ArchivePath).Path
$destination = [IO.Path]::GetFullPath($DestinationPrivateDirectory)
if (Test-Path -LiteralPath $destination) { throw 'Recovery destination already exists. Restore only into a clean private directory.' }
$sevenZip = Resolve-SevenZip -Requested $SevenZipPath
$extract = Join-Path ([IO.Path]::GetTempPath()) ('rst-recovery-extract-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $extract | Out-Null
    Protect-RSTPath -Path $extract -Directory
    Write-Host '7-Zip will securely request the recovery password locally. Do not paste the password into the AI conversation.'
    & $sevenZip x -p ("-o$extract") -y -- $archive | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Recovery archive extraction failed.' }
    Protect-RSTRecoveryTree -Root $extract
    $result = Restore-RSTExtractedRecovery -ExtractedDirectory $extract -PrivateDirectory $destination
    Write-Host 'RECOVERY_RESTORED=1'
    Write-Host 'REMOTE_INFRASTRUCTURE_CHANGED=0'
    Write-Host 'OBSERVED_STATE_RESET=1'
    $result | ConvertTo-Json -Depth 10 -Compress
}
finally {
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
}
