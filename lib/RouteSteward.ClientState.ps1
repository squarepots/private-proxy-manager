$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RSTClientCanonicalFingerprint {
    param(
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$PrivateDirectory
    )
    $inventoryFull = [IO.Path]::GetFullPath($InventoryPath)
    $privateFull = [IO.Path]::GetFullPath($PrivateDirectory)
    $secretsRoot = Join-Path $privateFull 'secrets'
    if (-not (Test-Path -LiteralPath $inventoryFull -PathType Leaf)) { throw 'Inventory is missing for ClientTarget fingerprinting.' }
    if (-not (Test-Path -LiteralPath $secretsRoot -PathType Container)) { throw 'Secret storage is missing for ClientTarget fingerprinting.' }

    $sha = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        function Add-RSTFingerprintPart {
            param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][byte[]]$Bytes)
            $nameBytes = [Text.Encoding]::UTF8.GetBytes($Name.Replace('\','/'))
            $lengthBytes = [BitConverter]::GetBytes([int64]$Bytes.LongLength)
            $sha.AppendData($nameBytes)
            $sha.AppendData([byte[]](0))
            $sha.AppendData($lengthBytes)
            $sha.AppendData($Bytes)
        }
        Add-RSTFingerprintPart -Name 'inventory.json' -Bytes ([IO.File]::ReadAllBytes($inventoryFull))
        foreach ($file in @(Get-ChildItem -LiteralPath $secretsRoot -Recurse -Force -File | Sort-Object FullName)) {
            $relative = [IO.Path]::GetRelativePath($secretsRoot, $file.FullName)
            Add-RSTFingerprintPart -Name ('secrets/' + $relative.Replace('\','/')) -Bytes ([IO.File]::ReadAllBytes($file.FullName))
        }
        return [Convert]::ToHexString($sha.GetHashAndReset()).ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-RSTClientRenderManifestPath {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    return Join-Path ([IO.Path]::GetFullPath($PrivateDirectory)) 'delivery\client-render-manifest.json'
}

function Read-RSTClientRenderManifest {
    param([Parameter(Mandatory)][string]$PrivateDirectory, [switch]$AllowMissing)
    $path = Get-RSTClientRenderManifestPath -PrivateDirectory $PrivateDirectory
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($AllowMissing) { return [pscustomobject][ordered]@{ schema = 1; targets = @() } }
        throw 'Client render manifest is missing.'
    }
    $manifest = Read-RSTJson -Path $path -Label 'Client render manifest'
    if ([int](Get-RSTOptional $manifest 'schema' 0) -ne 1) { throw 'Client render manifest schema must be 1.' }
    return $manifest
}

function Update-RSTClientRenderManifest {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [Parameter(Mandatory)][object[]]$Outputs
    )
    $manifest = Read-RSTClientRenderManifest -PrivateDirectory $PrivateDirectory -AllowMissing
    $fingerprint = Get-RSTClientCanonicalFingerprint -InventoryPath $InventoryPath -PrivateDirectory $PrivateDirectory
    $map = @{}
    foreach ($entry in @(Get-RSTOptional $manifest 'targets' @())) { $map[[string]$entry.id] = $entry }
    foreach ($output in $Outputs) {
        $targetId = [string](Get-RSTOptional $output 'client_target')
        $path = [string](Get-RSTOptional $output 'path')
        if (-not $targetId -or -not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'A rendered ClientTarget output is incomplete.' }
        $target = Get-RSTClientTargetById -Inventory $Inventory -Id $targetId
        $map[$targetId] = [pscustomobject][ordered]@{
            id = $targetId
            renderer = [string]$target.renderer
            file_name = [IO.Path]::GetFileName($path)
            output_sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            input_fingerprint = $fingerprint
            rendered_at = [DateTime]::UtcNow.ToString('o')
        }
    }
    $validIds = @(Get-RSTClientTargets -Inventory $Inventory | ForEach-Object { [string]$_.id })
    $next = [ordered]@{
        schema = 1
        targets = @($map.Keys | Where-Object { $validIds -contains $_ } | Sort-Object | ForEach-Object { $map[$_] })
    }
    Write-RSTJsonAtomic -Value $next -Path (Get-RSTClientRenderManifestPath -PrivateDirectory $PrivateDirectory)
    return $next
}

function Get-RSTClientRenderDrift {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$PrivateDirectory
    )
    $manifest = Read-RSTClientRenderManifest -PrivateDirectory $PrivateDirectory -AllowMissing
    $fingerprint = Get-RSTClientCanonicalFingerprint -InventoryPath $InventoryPath -PrivateDirectory $PrivateDirectory
    $map = @{}
    foreach ($entry in @(Get-RSTOptional $manifest 'targets' @())) { $map[[string]$entry.id] = $entry }
    $delivery = [string](Get-RSTOptional $Inventory.delivery 'directory' (Join-Path $PrivateDirectory 'delivery'))
    $items = [Collections.Generic.List[object]]::new()
    foreach ($target in @(Get-RSTClientTargets -Inventory $Inventory | Sort-Object id)) {
        $id = [string]$target.id
        $entry = $map[$id]
        $category = 'in-sync'
        if (-not $entry) { $category = 'client-render-stale' }
        elseif ([string](Get-RSTOptional $entry 'input_fingerprint') -ne $fingerprint) { $category = 'client-render-stale' }
        else {
            $fileName = [string](Get-RSTOptional $entry 'file_name')
            if (-not $fileName -or [IO.Path]::GetFileName($fileName) -ne $fileName) { $category = 'client-render-stale' }
            else {
                $path = Join-Path $delivery $fileName
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $category = 'client-render-stale' }
                else {
                    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($hash -ne [string](Get-RSTOptional $entry 'output_sha256')) { $category = 'client-render-stale' }
                }
            }
        }
        $items.Add([ordered]@{
            id = 'client-target:' + $id
            target = $id
            category = $category
            severity = if ($category -eq 'in-sync') { 'info' } else { 'warning' }
            desired = 'current-with-canonical-state'
            observed = if ($category -eq 'in-sync') { 'current' } else { 'stale-or-missing' }
        })
    }
    return @($items)
}
