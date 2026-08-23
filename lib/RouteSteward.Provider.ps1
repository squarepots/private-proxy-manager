$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RSTProviderById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id, [switch]$AllowMissing)
    $matches = @($Inventory.providers | Where-Object { $_.id -eq $Id })
    if ($matches.Count -eq 0 -and $AllowMissing) { return $null }
    if ($matches.Count -ne 1) { throw "Unknown Provider '$Id'." }
    return $matches[0]
}

function Test-RSTProviderUrl {
    param([Parameter(Mandatory)][string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -match '[\r\n]') { return $false }
    $uri = $null
    return [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -in @('http','https')
}

function Save-RSTProviderUrlSecret {
    param(
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$PrivateDirectory
    )
    if (-not (Test-RSTProviderUrl -Url $Url)) { throw 'Provider URL must be an absolute HTTP(S) URL without line breaks.' }
    $secretIndex = Read-RSTSecretIndex -PrivateDirectory $PrivateDirectory
    $reference = "provider:$ProviderId"
    $relative = "providers/$ProviderId.url"
    $path = Join-Path (Join-Path $PrivateDirectory 'secrets') $relative
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Protect-RSTPath -Path $parent -Directory
    [IO.File]::WriteAllText($path, $Url.Trim() + "`n", [Text.UTF8Encoding]::new($false))
    Protect-RSTPath -Path $path
    $property = $secretIndex.refs.PSObject.Properties[$reference]
    if ($property) {
        $property.Value.path = $relative
        $property.Value.type = 'url'
    }
    else {
        $secretIndex.refs | Add-Member -NotePropertyName $reference -NotePropertyValue ([pscustomobject][ordered]@{ type = 'url'; path = $relative })
    }
    Write-RSTJsonAtomic -Value $secretIndex -Path (Join-Path $PrivateDirectory 'secrets\index.json')
    return $reference
}

function Add-RSTProvider {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)]$Context
    )
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $id = ConvertTo-RSTId ([string]$Context.provider_id)
    if (Get-RSTProviderById -Inventory $Inventory -Id $id -AllowMissing) { throw "Provider '$id' already exists." }
    $url = [string]$Context.url
    if (-not (Test-RSTProviderUrl -Url $url)) { throw 'Provider URL must be an absolute HTTP(S) URL without line breaks.' }
    $interval = [int](Get-RSTOptional $Context 'interval_seconds' 86400)
    if ($interval -lt 3600) { throw 'Provider refresh interval must be at least one hour.' }
    $provider = [pscustomobject][ordered]@{
        id = $id
        display_name = [string](Get-RSTOptional $Context 'display_name' $id)
        source_type = 'mihomo-http'
        source_secret_ref = "provider:$id"
        interval_seconds = $interval
        health_check = $false
        enabled = [bool](Get-RSTOptional $Context 'enabled' $true)
    }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.providers = @($candidate.providers) + $provider
    $null = Assert-RSTInventory -Inventory $candidate -PrivateDirectory $privateDirectory -SkipSecretCheck
    $secretCreated = $false
    try {
        $provider.source_secret_ref = Save-RSTProviderUrlSecret -ProviderId $id -Url $url -PrivateDirectory $privateDirectory
        $secretCreated = $true
        Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
        return $provider
    }
    catch {
        if ($secretCreated) { Remove-RSTProviderSecret -ProviderId $id -PrivateDirectory $privateDirectory -IgnoreMissing }
        throw
    }
}

function Update-RSTProvider {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$ProviderId,
        [Parameter(Mandatory)]$Context
    )
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $null = Get-RSTProviderById -Inventory $Inventory -Id $ProviderId
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $provider = Get-RSTProviderById -Inventory $candidate -Id $ProviderId

    $newUrl = $null
    if ($Context.PSObject.Properties['url']) {
        $newUrl = [string]$Context.url
        if (-not (Test-RSTProviderUrl -Url $newUrl)) { throw 'Provider URL must be an absolute HTTP(S) URL without line breaks.' }
    }
    if ($Context.PSObject.Properties['display_name']) { $provider.display_name = [string]$Context.display_name }
    if ($Context.PSObject.Properties['interval_seconds']) {
        $interval = [int]$Context.interval_seconds
        if ($interval -lt 3600) { throw 'Provider refresh interval must be at least one hour.' }
        $provider.interval_seconds = $interval
    }
    if ($Context.PSObject.Properties['enabled']) { $provider.enabled = [bool]$Context.enabled }
    $provider.health_check = $false
    $null = Assert-RSTInventory -Inventory $candidate -PrivateDirectory $privateDirectory -SkipSecretCheck

    $oldUrl = $null
    if ($null -ne $newUrl) {
        $oldPath = Resolve-RSTSecret -Reference ([string]$provider.source_secret_ref) -PrivateDirectory $privateDirectory
        $oldUrl = [IO.File]::ReadAllText($oldPath, [Text.Encoding]::UTF8).Trim()
    }
    try {
        if ($null -ne $newUrl) { $provider.source_secret_ref = Save-RSTProviderUrlSecret -ProviderId $ProviderId -Url $newUrl -PrivateDirectory $privateDirectory }
        Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
        return $provider
    }
    catch {
        if ($null -ne $oldUrl) {
            try { $null = Save-RSTProviderUrlSecret -ProviderId $ProviderId -Url $oldUrl -PrivateDirectory $privateDirectory }
            catch { }
        }
        throw
    }
}

function Remove-RSTProviderSecret {
    param([Parameter(Mandatory)][string]$ProviderId, [Parameter(Mandatory)][string]$PrivateDirectory, [switch]$IgnoreMissing)
    $reference = "provider:$ProviderId"
    $secretIndex = Read-RSTSecretIndex -PrivateDirectory $PrivateDirectory
    $property = $secretIndex.refs.PSObject.Properties[$reference]
    if (-not $property) {
        if ($IgnoreMissing) { return }
        throw "Provider secret '$reference' is not registered."
    }
    $path = Resolve-RSTSecret -Reference $reference -PrivateDirectory $PrivateDirectory -Index $secretIndex
    Remove-Item -LiteralPath $path -Force
    $secretIndex.refs.PSObject.Properties.Remove($reference)
    Write-RSTJsonAtomic -Value $secretIndex -Path (Join-Path $PrivateDirectory 'secrets\index.json')
}

function Remove-RSTProvider {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$ProviderId
    )
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $null = Get-RSTProviderById -Inventory $Inventory -Id $ProviderId
    $references = @($Inventory.profiles | Where-Object { @(Get-RSTOptional $_ 'include_providers' @()) -contains $ProviderId })
    if ($references.Count) { throw "Provider '$ProviderId' is still referenced by one or more Profiles." }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.providers = @($candidate.providers | Where-Object { $_.id -ne $ProviderId })
    $null = Assert-RSTInventory -Inventory $candidate -PrivateDirectory $privateDirectory -SkipSecretCheck
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath -SkipSecretCheck
    try {
        Remove-RSTProviderSecret -ProviderId $ProviderId -PrivateDirectory $privateDirectory
    }
    catch {
        try { Save-RSTInventory -Inventory $Inventory -InventoryPath $InventoryPath }
        catch { }
        throw
    }
    return [ordered]@{ id = $ProviderId; removed = $true }
}
