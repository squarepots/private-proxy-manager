$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-RSTCleanInventory {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    $privatePath = [IO.Path]::GetFullPath($PrivateDirectory)
    $now = [DateTime]::UtcNow.ToString('o')
    return [ordered]@{
        schema = 1
        metadata = [ordered]@{
            id = 'route-steward'
            created_at = $now
            updated_at = $now
        }
        delivery = [ordered]@{
            directory = (Join-Path $privatePath 'delivery')
            recovery_directory = (Join-Path $privatePath 'recovery')
        }
        servers = @()
        links = @()
        routes = @()
        providers = @()
        policies = @(Get-RSTDefaultPolicies)
        profiles = @()
        client_targets = @()
    }
}

function Get-RSTClientTargets {
    param([Parameter(Mandatory)]$Inventory)
    return @(Get-RSTOptional $Inventory 'client_targets' @())
}

function Get-RSTClientTargetById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id, [switch]$AllowMissing)
    $matches = @(Get-RSTClientTargets -Inventory $Inventory | Where-Object { $_.id -eq $Id })
    if ($matches.Count -eq 0 -and $AllowMissing) { return $null }
    if ($matches.Count -ne 1) { throw "Unknown ClientTarget '$Id'." }
    return $matches[0]
}

function Get-RSTProfileById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id, [switch]$AllowMissing)
    $matches = @($Inventory.profiles | Where-Object { $_.id -eq $Id })
    if ($matches.Count -eq 0 -and $AllowMissing) { return $null }
    if ($matches.Count -ne 1) { throw "Unknown Profile '$Id'." }
    return $matches[0]
}

function Get-RSTProfileForClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$ClientTarget)
    return Get-RSTProfileById -Inventory $Inventory -Id ([string]$ClientTarget.profile)
}

function Save-RSTInventory {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [switch]$SkipSecretCheck)
    if (-not $Inventory.PSObject.Properties['metadata']) { $Inventory | Add-Member -NotePropertyName metadata -NotePropertyValue ([pscustomobject]@{}) }
    $Inventory.metadata | Add-Member -NotePropertyName updated_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $null = Assert-RSTInventory -Inventory $Inventory -PrivateDirectory $privateDirectory -SkipSecretCheck:$SkipSecretCheck
    Write-RSTJsonAtomic -Value $Inventory -Path $InventoryPath
}

function Add-RSTProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $id = ConvertTo-RSTId ([string]$Context.profile_id)
    if (Get-RSTProfileById -Inventory $Inventory -Id $id -AllowMissing) { throw "Profile '$id' already exists." }
    $profile = [pscustomobject][ordered]@{
        id = $id
        policy = [string](Get-RSTOptional $Context 'policy' '')
        include_routes = @(Get-RSTOptional $Context 'include_routes' @('*'))
        include_providers = @(Get-RSTOptional $Context 'include_providers' @())
    }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.profiles = @($candidate.profiles) + $profile
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $profile
}

function Update-RSTProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$ProfileId, [Parameter(Mandatory)]$Context)
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $profile = Get-RSTProfileById -Inventory $candidate -Id $ProfileId
    if ($Context.PSObject.Properties['policy']) { $profile.policy = [string]$Context.policy }
    if ($Context.PSObject.Properties['include_routes']) { $profile.include_routes = @($Context.include_routes) }
    if ($Context.PSObject.Properties['include_providers']) { $profile.include_providers = @($Context.include_providers) }
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $profile
}

function Remove-RSTProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$ProfileId)
    $null = Get-RSTProfileById -Inventory $Inventory -Id $ProfileId
    if (@(Get-RSTClientTargets -Inventory $Inventory | Where-Object { $_.profile -eq $ProfileId }).Count) { throw "Profile '$ProfileId' is still referenced by a ClientTarget." }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.profiles = @($candidate.profiles | Where-Object { $_.id -ne $ProfileId })
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [ordered]@{ id = $ProfileId; removed = $true }
}

function Add-RSTClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $id = ConvertTo-RSTId ([string]$Context.target_id)
    if (Get-RSTClientTargetById -Inventory $Inventory -Id $id -AllowMissing) { throw "ClientTarget '$id' already exists." }
    $renderer = [string]$Context.renderer
    if ($renderer -notin @('mihomo','shadowrocket','hysteria2')) { throw "Unsupported ClientTarget renderer '$renderer'." }
    $profileId = [string]$Context.profile_id
    $null = Get-RSTProfileById -Inventory $Inventory -Id $profileId
    $target = [ordered]@{
        id = $id
        profile = $profileId
        renderer = $renderer
        delivery = if ($renderer -eq 'shadowrocket') { [string](Get-RSTOptional $Context 'delivery' 'nodes') } else { 'file' }
    }
    if ($renderer -eq 'shadowrocket') { $target.qr = Get-RSTOptional $Context 'qr' ([ordered]@{ default_mode = 'batch'; target_utf8_bytes = 2400; size_px = 220; max_viewport_height = 40 }) }
    if ($renderer -eq 'hysteria2') {
        $target.route = [string](Get-RSTOptional $Context 'route_id')
        $target.listen = [string](Get-RSTOptional $Context 'listen' '127.0.0.1:1080')
        $target.ingress_family = [string](Get-RSTOptional $Context 'ingress_family' 'auto')
    }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.client_targets = @($candidate.client_targets) + [pscustomobject]$target
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [pscustomobject]$target
}

function Update-RSTClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$TargetId, [Parameter(Mandatory)]$Context)
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $target = Get-RSTClientTargetById -Inventory $candidate -Id $TargetId
    if ($Context.PSObject.Properties['profile_id']) { $target.profile = [string]$Context.profile_id }
    if ($Context.PSObject.Properties['delivery']) {
        if ((Get-RSTOptional $target 'subscription_secret_ref') -and [string]$Context.delivery -ne 'subscription') { throw 'A subscription-backed ClientTarget must revoke its subscription state before changing delivery mode.' }
        $target.delivery = [string]$Context.delivery
    }
    if ([string]$target.renderer -eq 'hysteria2') {
        if ($Context.PSObject.Properties['route_id']) { $target.route = [string]$Context.route_id }
        if ($Context.PSObject.Properties['listen']) { $target.listen = [string]$Context.listen }
        if ($Context.PSObject.Properties['ingress_family']) { $target.ingress_family = [string]$Context.ingress_family }
    }
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $target
}

function Remove-RSTClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$TargetId)
    $target = Get-RSTClientTargetById -Inventory $Inventory -Id $TargetId
    if (Get-RSTOptional $target 'subscription_secret_ref') { throw 'Revoke the ClientTarget subscription state before removing it.' }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.client_targets = @($candidate.client_targets | Where-Object { $_.id -ne $TargetId })
    Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [ordered]@{ id = $TargetId; removed = $true }
}
