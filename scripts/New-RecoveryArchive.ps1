[CmdletBinding()]
param(
    [string]$InventoryPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'private\inventory.json'),
    [string]$SevenZipPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\PrivateProxyManager.Core.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Model.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Agent.ps1')

function Resolve-SevenZip {
    param([string]$Requested)
    if ($Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
    foreach ($name in '7z', '7zz', '7z.exe') {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    if ($env:OS -eq 'Windows_NT') {
        $candidates = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path $env:ProgramFiles 'NanaZip\7z.exe'))
        if ($env:LOCALAPPDATA) {
            $apps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
            if (Test-Path -LiteralPath $apps) { $candidates += Get-ChildItem -Path $apps -Filter 7z.exe -Recurse -ErrorAction SilentlyContinue | ForEach-Object FullName }
        }
        $found = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($found) { return [IO.Path]::GetFullPath($found) }
    }
    throw '7-Zip (7z/7zz) was not found.'
}

function Copy-RecoveryFile {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw 'A recovery source file is missing.' }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

$InventoryPath = [IO.Path]::GetFullPath($InventoryPath)
$privateDirectory = Split-Path -Parent $InventoryPath
$inventory = Read-PPMStateInventory -Path $InventoryPath
$sevenZip = Resolve-SevenZip -Requested $SevenZipPath
$recoveryDirectory = [IO.Path]::GetFullPath([string]$inventory.delivery.recovery_directory)
New-Item -ItemType Directory -Force -Path $recoveryDirectory | Out-Null
Protect-PPMPath -Path $recoveryDirectory -Directory
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$archive = Join-Path $recoveryDirectory "private-proxy-manager-recovery-$stamp.7z"
$stage = Join-Path ([IO.Path]::GetTempPath()) ('private-proxy-manager-recovery-' + [Guid]::NewGuid().ToString('N'))
$verified = $false
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    Protect-PPMPath -Path $stage -Directory
    Copy-RecoveryFile -Source $InventoryPath -Destination (Join-Path $stage 'private\inventory.json')
    foreach ($name in 'observed.json') {
        $source = Join-Path $privateDirectory $name
        if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-RecoveryFile -Source $source -Destination (Join-Path $stage "private\$name") }
    }
    Copy-Item -LiteralPath (Join-Path $privateDirectory 'secrets') -Destination (Join-Path $stage 'private\secrets') -Recurse

    foreach ($server in @($inventory.servers)) {
        $source = [IO.Path]::GetFullPath([string]$server.ssh.key_path)
        $destination = Join-Path $stage ('ssh\{0}\{1}' -f $server.id, [IO.Path]::GetFileName($source))
        Copy-RecoveryFile -Source $source -Destination $destination
    }

    $remote = (& git -C $repo remote get-url origin 2>$null | Select-Object -First 1)
    $commit = (& git -C $repo rev-parse HEAD 2>$null | Select-Object -First 1)
    $metadata = [ordered]@{
        schema = 1
        created_at = [DateTime]::UtcNow.ToString('o')
        product = 'private-proxy-manager'
        product_version = Get-PPMProductVersion
        repository = $remote
        commit = $commit
        inventory_schema = 1
        recovery_model = 'agent-native-local-state'
    }
    [IO.File]::WriteAllText((Join-Path $stage 'RECOVERY-METADATA.json'), ($metadata | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $startHere = @"
# Private Proxy Manager recovery

Give this encrypted recovery archive and the Private Proxy Manager repository to a supported capable AI agent and say:

> Recover my Private Proxy Manager state from this archive. Do not mutate remote infrastructure until the restored local state has been validated and audited.

The agent should read the repository's canonical Skill, restore the archive through the repository-owned recovery workflow, validate inventory/secret references and local permissions, inspect drift, and audit existing Routes before any remote write.

The archive contains live proxy credentials and SSH private keys. Enter the archive password only into the local secure 7-Zip prompt initiated by the recovery workflow; do not paste it into the AI conversation, repository files, process arguments, or logs.

Observed state is disposable evidence. Restored desired state and secrets are canonical, but they do not prove remote infrastructure still matches them.
"@
    [IO.File]::WriteAllText((Join-Path $stage 'START-HERE.md'), $startHere, [Text.UTF8Encoding]::new($false))

    $manifestLines = Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    [IO.File]::WriteAllLines((Join-Path $stage 'SHA256SUMS'), $manifestLines, [Text.UTF8Encoding]::new($false))
    Get-ChildItem -LiteralPath $stage -Recurse | ForEach-Object { Protect-PPMPath -Path $_.FullName -Directory:$_.PSIsContainer }

    Write-Host '7-Zip will securely request the recovery password locally. The password is not passed as a command argument or logged.'
    & $sevenZip a -t7z -mhe=on -mx=7 -p -- $archive (Join-Path $stage '*') | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Encrypted recovery archive creation failed.' }
    Protect-PPMPath -Path $archive
    Write-Host 'Re-enter the password locally so 7-Zip can verify the encrypted archive.'
    & $sevenZip t -p -- $archive | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Encrypted recovery archive verification failed.' }
    $verified = $true
    Write-Host "Encrypted recovery archive is ready: $archive"
}
finally {
    if (Test-Path -LiteralPath $stage) {
        $resolvedStage = [IO.Path]::GetFullPath($stage)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a recovery stage outside the temporary directory.' }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
    if (-not $verified -and (Test-Path -LiteralPath $archive -PathType Leaf)) { Remove-Item -LiteralPath $archive -Force }
}
