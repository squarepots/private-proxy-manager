$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-PPMCleanInventory {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    $privatePath = [IO.Path]::GetFullPath($PrivateDirectory)
    $now = [DateTime]::UtcNow.ToString('o')
    return [ordered]@{
        schema = 1
        metadata = [ordered]@{
            id = 'private-proxy-manager'
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
        policies = @(Get-PPMDefaultPolicies)
        profiles = @()
        client_targets = @()
    }
}

function Get-PPMClientTargets {
    param([Parameter(Mandatory)]$Inventory)
    return @(Get-PPMOptional $Inventory 'client_targets' @())
}

function Get-PPMClientTargetById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id, [switch]$AllowMissing)
    $matches = @(Get-PPMClientTargets -Inventory $Inventory | Where-Object { $_.id -eq $Id })
    if ($matches.Count -eq 0 -and $AllowMissing) { return $null }
    if ($matches.Count -ne 1) { throw "Unknown ClientTarget '$Id'." }
    return $matches[0]
}

function Get-PPMProfileById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id, [switch]$AllowMissing)
    $matches = @($Inventory.profiles | Where-Object { $_.id -eq $Id })
    if ($matches.Count -eq 0 -and $AllowMissing) { return $null }
    if ($matches.Count -ne 1) { throw "Unknown Profile '$Id'." }
    return $matches[0]
}

function Get-PPMProfileForClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$ClientTarget)
    return Get-PPMProfileById -Inventory $Inventory -Id ([string]$ClientTarget.profile)
}

function Save-PPMInventory {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [switch]$SkipSecretCheck)
    if (-not $Inventory.PSObject.Properties['metadata']) { $Inventory | Add-Member -NotePropertyName metadata -NotePropertyValue ([pscustomobject]@{}) }
    $Inventory.metadata | Add-Member -NotePropertyName updated_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $null = Assert-PPMInventory -Inventory $Inventory -PrivateDirectory $privateDirectory -SkipSecretCheck:$SkipSecretCheck
    Write-PPMJsonAtomic -Value $Inventory -Path $InventoryPath
}

function Add-PPMProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $id = ConvertTo-PPMId ([string]$Context.profile_id)
    if (Get-PPMProfileById -Inventory $Inventory -Id $id -AllowMissing) { throw "Profile '$id' already exists." }
    $profile = [pscustomobject][ordered]@{
        id = $id
        policy = [string](Get-PPMOptional $Context 'policy' '')
        include_routes = @(Get-PPMOptional $Context 'include_routes' @('*'))
        include_providers = @(Get-PPMOptional $Context 'include_providers' @())
    }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.profiles = @($candidate.profiles) + $profile
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $profile
}

function Update-PPMProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$ProfileId, [Parameter(Mandatory)]$Context)
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $profile = Get-PPMProfileById -Inventory $candidate -Id $ProfileId
    if ($Context.PSObject.Properties['policy']) { $profile.policy = [string]$Context.policy }
    if ($Context.PSObject.Properties['include_routes']) { $profile.include_routes = @($Context.include_routes) }
    if ($Context.PSObject.Properties['include_providers']) { $profile.include_providers = @($Context.include_providers) }
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $profile
}

function Remove-PPMProfile {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$ProfileId)
    $null = Get-PPMProfileById -Inventory $Inventory -Id $ProfileId
    if (@(Get-PPMClientTargets -Inventory $Inventory | Where-Object { $_.profile -eq $ProfileId }).Count) { throw "Profile '$ProfileId' is still referenced by a ClientTarget." }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.profiles = @($candidate.profiles | Where-Object { $_.id -ne $ProfileId })
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [ordered]@{ id = $ProfileId; removed = $true }
}

function Add-PPMClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $id = ConvertTo-PPMId ([string]$Context.target_id)
    if (Get-PPMClientTargetById -Inventory $Inventory -Id $id -AllowMissing) { throw "ClientTarget '$id' already exists." }
    $renderer = [string]$Context.renderer
    if ($renderer -notin @('mihomo','shadowrocket')) { throw "Unsupported ClientTarget renderer '$renderer'." }
    $profileId = [string]$Context.profile_id
    $null = Get-PPMProfileById -Inventory $Inventory -Id $profileId
    $target = [ordered]@{
        id = $id
        profile = $profileId
        renderer = $renderer
        delivery = if ($renderer -eq 'mihomo') { 'file' } else { [string](Get-PPMOptional $Context 'delivery' 'nodes') }
    }
    if ($renderer -eq 'shadowrocket') { $target.qr = Get-PPMOptional $Context 'qr' ([ordered]@{ default_mode = 'batch'; target_utf8_bytes = 2400; size_px = 220; max_viewport_height = 40 }) }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.client_targets = @($candidate.client_targets) + [pscustomobject]$target
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [pscustomobject]$target
}

function Update-PPMClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$TargetId, [Parameter(Mandatory)]$Context)
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $target = Get-PPMClientTargetById -Inventory $candidate -Id $TargetId
    if ($Context.PSObject.Properties['profile_id']) { $target.profile = [string]$Context.profile_id }
    if ($Context.PSObject.Properties['delivery']) {
        if ((Get-PPMOptional $target 'subscription_secret_ref') -and [string]$Context.delivery -ne 'subscription') { throw 'A subscription-backed ClientTarget must revoke its subscription state before changing delivery mode.' }
        $target.delivery = [string]$Context.delivery
    }
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return $target
}

function Remove-PPMClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)][string]$TargetId)
    $target = Get-PPMClientTargetById -Inventory $Inventory -Id $TargetId
    if (Get-PPMOptional $target 'subscription_secret_ref') { throw 'Revoke the ClientTarget subscription state before removing it.' }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.client_targets = @($candidate.client_targets | Where-Object { $_.id -ne $TargetId })
    Save-PPMInventory -Inventory $candidate -InventoryPath $InventoryPath
    return [ordered]@{ id = $TargetId; removed = $true }
}
