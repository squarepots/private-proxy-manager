$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-PPMRecoveryManifest {
    param([Parameter(Mandatory)][string]$ExtractedDirectory)
    $root = [IO.Path]::GetFullPath($ExtractedDirectory)
    $manifestPath = Join-Path $root 'SHA256SUMS'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Recovery archive is missing SHA256SUMS.' }
    $comparison = if ($env:OS -eq 'Windows_NT') { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $verified = 0
    foreach ($line in [IO.File]::ReadAllLines($manifestPath, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^(?<hash>[0-9a-fA-F]{64})  (?<path>.+)$') { throw 'Recovery manifest contains an invalid entry.' }
        $relative = $Matches.path.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Recovery manifest contains an unsafe path.' }
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, $comparison)) { throw 'Recovery manifest path escapes the extracted archive.' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Recovery archive is missing a file declared by its manifest.' }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $Matches.hash.ToLowerInvariant()) { throw 'Recovery archive failed SHA-256 manifest verification.' }
        $verified++
    }
    if ($verified -lt 2) { throw 'Recovery manifest is unexpectedly small.' }
    return $verified
}

function Protect-PPMRecoveryTree {
    param([Parameter(Mandatory)][string]$Root)
    Protect-PPMPath -Path $Root -Directory
    Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object { Protect-PPMPath -Path $_.FullName -Directory:$_.PSIsContainer }
}

function Restore-PPMExtractedRecovery {
    param(
        [Parameter(Mandatory)][string]$ExtractedDirectory,
        [Parameter(Mandatory)][string]$PrivateDirectory
    )
    $sourceRoot = [IO.Path]::GetFullPath($ExtractedDirectory)
    $target = [IO.Path]::GetFullPath($PrivateDirectory)
    if (Test-Path -LiteralPath $target) { throw 'Recovery destination already exists. Restore only into a clean private directory.' }
    if (@(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force | Where-Object { $_.LinkType }).Count) { throw 'Recovery archive contains symbolic links or reparse points.' }

    $verifiedFiles = Test-PPMRecoveryManifest -ExtractedDirectory $sourceRoot
    $metadataPath = Join-Path $sourceRoot 'RECOVERY-METADATA.json'
    $sourcePrivate = Join-Path $sourceRoot 'private'
    $sourceInventory = Join-Path $sourcePrivate 'inventory.json'
    $sourceSecrets = Join-Path $sourcePrivate 'secrets'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceInventory -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $sourceSecrets 'index.json') -PathType Leaf)) {
        throw 'Recovery archive does not contain complete PPM canonical state.'
    }
    $metadata = Read-PPMJson -Path $metadataPath -Label 'Recovery metadata'
    $metadataSchema = [int](Get-PPMOptional $metadata 'inventory_schema' 0)
    if ([string](Get-PPMOptional $metadata 'product') -ne 'private-proxy-manager' -or $metadataSchema -ne 1) {
        throw 'Recovery archive metadata is not compatible with this PPM recovery workflow.'
    }

    $inventory = Read-PPMJson -Path $sourceInventory -Label 'Recovered inventory'
    $sourceSchema = [int](Get-PPMOptional $inventory 'schema' 0)
    if ($sourceSchema -ne 1 -or $sourceSchema -ne $metadataSchema) { throw 'Recovered inventory schema is unsupported or disagrees with recovery metadata.' }
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $stage = Join-Path $parent ('.ppm-restore-' + [Guid]::NewGuid().ToString('N'))
    $moved = $false
    $completed = $false
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Protect-PPMPath -Path $stage -Directory
        Copy-Item -LiteralPath $sourceSecrets -Destination (Join-Path $stage 'secrets') -Recurse
        New-Item -ItemType Directory -Force -Path (Join-Path $stage 'ssh'), (Join-Path $stage 'delivery'), (Join-Path $stage 'recovery') | Out-Null

        foreach ($server in @($inventory.servers)) {
            $serverId = [string]$server.id
            $sourceSshDirectory = Join-Path $sourceRoot (Join-Path 'ssh' $serverId)
            $keys = @(if (Test-Path -LiteralPath $sourceSshDirectory -PathType Container) { Get-ChildItem -LiteralPath $sourceSshDirectory -File -Force })
            if ($keys.Count -ne 1) { throw "Recovery archive must contain exactly one SSH private key for Server '$serverId'." }
            $destinationDirectory = Join-Path (Join-Path $stage 'ssh') $serverId
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
            $destinationKey = Join-Path $destinationDirectory $keys[0].Name
            Copy-Item -LiteralPath $keys[0].FullName -Destination $destinationKey
            $server.ssh.key_path = [IO.Path]::GetFullPath((Join-Path $target (Join-Path (Join-Path 'ssh' $serverId) $keys[0].Name)))
        }

        $inventory.delivery.directory = [IO.Path]::GetFullPath((Join-Path $target 'delivery'))
        $inventory.delivery.recovery_directory = [IO.Path]::GetFullPath((Join-Path $target 'recovery'))
        if (-not $inventory.PSObject.Properties['metadata']) { $inventory | Add-Member -NotePropertyName metadata -NotePropertyValue ([pscustomobject]@{}) }
        $inventory.metadata | Add-Member -NotePropertyName recovered_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force

        Write-PPMJsonAtomic -Value $inventory -Path (Join-Path $stage 'inventory.json')
        Write-PPMJsonAtomic -Value ([ordered]@{ schema = 1; generated_at = $null; servers = @(); links = @(); routes = @() }) -Path (Join-Path $stage 'observed.json')
        Protect-PPMRecoveryTree -Root $stage

        $validationInventory = Read-PPMInventory -Path (Join-Path $stage 'inventory.json')
        foreach ($server in @($validationInventory.servers)) {
            $relative = [IO.Path]::GetRelativePath($target, [string]$server.ssh.key_path)
            if ($relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative)) { throw 'Recovered SSH key path leaves the private directory.' }
            $stageKey = Join-Path $stage $relative
            if (-not (Test-Path -LiteralPath $stageKey -PathType Leaf)) { throw 'Recovered SSH key relocation failed validation.' }
        }

        Move-Item -LiteralPath $stage -Destination $target
        $moved = $true
        Protect-PPMRecoveryTree -Root $target
        $finalInventory = Read-PPMInventory -Path (Join-Path $target 'inventory.json')
        foreach ($server in @($finalInventory.servers)) {
            if (-not (Test-Path -LiteralPath ([string]$server.ssh.key_path) -PathType Leaf)) { throw 'Recovered SSH key is missing at its final canonical path.' }
            if (-not (Test-PPMPrivateAcl -Path ([string]$server.ssh.key_path))) { throw 'Recovered SSH key permissions are not private.' }
        }
        $completed = $true
        return [ordered]@{
            restored = $true
            inventory_schema = [int]$finalInventory.schema
            servers = @($finalInventory.servers).Count
            links = @($finalInventory.links).Count
            routes = @($finalInventory.routes).Count
            providers = @($finalInventory.providers).Count
            manifest_files_verified = $verifiedFiles
            observed_state_reset = $true
            remote_changed = $false
        }
    }
    finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
        if ($moved -and -not $completed -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
}
