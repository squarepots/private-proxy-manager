$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:PPMDriftCategories = @(
    'in-sync','service-missing','remote-config-mismatch','firewall-network-mismatch',
    'wireguard-link-mismatch','hysteria-listener-mismatch','certificate-mismatch',
    'egress-mismatch','undetermined'
)

function Get-PPMObservedPath {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    return Join-Path ([IO.Path]::GetFullPath($PrivateDirectory)) 'observed.json'
}

function Read-PPMObservedState {
    param([Parameter(Mandatory)][string]$PrivateDirectory, [switch]$AllowMissing)
    $path = Get-PPMObservedPath -PrivateDirectory $PrivateDirectory
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($AllowMissing) { return [pscustomobject][ordered]@{ schema = 1; generated_at = $null; servers = @(); links = @(); routes = @() } }
        throw 'Observed state was not found.'
    }
    $observed = Read-PPMJson -Path $path -Label 'Observed state'
    if ([int](Get-PPMOptional $observed 'schema' 0) -ne 1) { throw 'Observed state schema must be 1.' }
    return $observed
}

function Save-PPMObservedState {
    param([Parameter(Mandatory)]$Observed, [Parameter(Mandatory)][string]$PrivateDirectory)
    $Observed.generated_at = [DateTime]::UtcNow.ToString('o')
    Write-PPMJsonAtomic -Value $Observed -Path (Get-PPMObservedPath -PrivateDirectory $PrivateDirectory)
}

function Set-PPMObservedRoute {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [Parameter(Mandatory)][string]$RouteId,
        [Parameter(Mandatory)][ValidateSet('healthy','unreachable','mismatch','undetermined')][string]$Status,
        [string]$Category,
        [string]$ActualEgressIPv4,
        [string]$HysteriaVersion,
        [string]$WireGuardVersion
    )
    $route = Get-PPMRouteById -Inventory $Inventory -Id $RouteId
    if (-not $Category) {
        $Category = if ($Status -eq 'healthy') { 'in-sync' } elseif ($Status -eq 'mismatch') { 'egress-mismatch' } else { 'undetermined' }
    }
    if ($Category -notin $script:PPMDriftCategories) { $Category = 'undetermined' }

    $observed = Read-PPMObservedState -PrivateDirectory $PrivateDirectory -AllowMissing
    $routeMap = @{}
    foreach ($item in @(Get-PPMOptional $observed 'routes' @())) { $routeMap[[string]$item.id] = $item }
    $routeMap[[string]$route.id] = [pscustomobject][ordered]@{
        id = [string]$route.id
        audit_status = $Status
        category = $Category
        audited_at = [DateTime]::UtcNow.ToString('o')
        actual_egress_ipv4 = if ($ActualEgressIPv4) { $ActualEgressIPv4 } else { $null }
        hysteria_version = if ($HysteriaVersion) { $HysteriaVersion } else { $null }
        wireguard_version = if ($WireGuardVersion) { $WireGuardVersion } else { $null }
    }
    $validRouteIds = @($Inventory.routes | ForEach-Object { [string]$_.id })
    $observed.routes = @($routeMap.Keys | Where-Object { $validRouteIds -contains $_ } | Sort-Object | ForEach-Object { $routeMap[$_] })

    $serverMap = @{}
    foreach ($item in @(Get-PPMOptional $observed 'servers' @())) { $serverMap[[string]$item.id] = $item }
    foreach ($serverId in @([string]$route.entry_server, [string]$route.exit_server) | Sort-Object -Unique) {
        $serverMap[$serverId] = [pscustomobject][ordered]@{
            id = $serverId
            audit_status = if ($Status -eq 'healthy') { 'reachable' } elseif ($Category -eq 'service-missing') { 'unhealthy' } else { 'unknown' }
            audited_at = [DateTime]::UtcNow.ToString('o')
        }
    }
    $validServerIds = @($Inventory.servers | ForEach-Object { [string]$_.id })
    $observed.servers = @($serverMap.Keys | Where-Object { $validServerIds -contains $_ } | Sort-Object | ForEach-Object { $serverMap[$_] })

    if ([string]$route.kind -eq 'relay' -and (Get-PPMOptional $route 'link')) {
        $linkMap = @{}
        foreach ($item in @(Get-PPMOptional $observed 'links' @())) { $linkMap[[string]$item.id] = $item }
        $linkMap[[string]$route.link] = [pscustomobject][ordered]@{
            id = [string]$route.link
            audit_status = if ($Status -eq 'healthy') { 'healthy' } elseif ($Category -eq 'wireguard-link-mismatch') { 'mismatch' } else { 'unknown' }
            audited_at = [DateTime]::UtcNow.ToString('o')
        }
        $validLinkIds = @($Inventory.links | ForEach-Object { [string]$_.id })
        $observed.links = @($linkMap.Keys | Where-Object { $validLinkIds -contains $_ } | Sort-Object | ForEach-Object { $linkMap[$_] })
    }

    Save-PPMObservedState -Observed $observed -PrivateDirectory $PrivateDirectory
    return $routeMap[[string]$route.id]
}

function Get-PPMDriftSeverity {
    param([Parameter(Mandatory)][string]$Category)
    if ($Category -in @('in-sync','disabled')) { return 'info' }
    if ($Category -in @('never-audited','undetermined','client-render-stale')) { return 'warning' }
    return 'error'
}

function Get-PPMDriftReport {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [string]$InventoryPath
    )
    if (-not $InventoryPath) { $InventoryPath = Join-Path ([IO.Path]::GetFullPath($PrivateDirectory)) 'inventory.json' }
    $observed = Read-PPMObservedState -PrivateDirectory $PrivateDirectory -AllowMissing
    $observedByRoute = @{}
    foreach ($item in @(Get-PPMOptional $observed 'routes' @())) { $observedByRoute[[string]$item.id] = $item }
    $items = [Collections.Generic.List[object]]::new()

    foreach ($route in @($Inventory.routes | Sort-Object order)) {
        $enabled = (Get-PPMOptional $route 'enabled' $true) -ne $false
        $state = $observedByRoute[[string]$route.id]
        if (-not $enabled) {
            $items.Add([ordered]@{ id = [string]$route.id; category = 'disabled'; severity = 'info'; desired = 'disabled'; observed = if ($state) { [string](Get-PPMOptional $state 'audit_status' 'unknown') } else { 'not-observed' } })
            continue
        }
        if (-not $state) {
            $items.Add([ordered]@{ id = [string]$route.id; category = 'never-audited'; severity = 'warning'; desired = 'enabled'; observed = 'not-observed' })
            continue
        }

        $category = [string](Get-PPMOptional $state 'category')
        if (-not $category) {
            $auditStatus = [string](Get-PPMOptional $state 'audit_status' 'unknown')
            $category = if ($auditStatus -eq 'healthy') { 'in-sync' } elseif ($auditStatus -eq 'mismatch') { 'egress-mismatch' } else { 'undetermined' }
        }
        if ($category -notin $script:PPMDriftCategories) { $category = 'undetermined' }
        $items.Add([ordered]@{
            id = [string]$route.id
            category = $category
            severity = Get-PPMDriftSeverity -Category $category
            desired = 'enabled'
            observed = if ($category -eq 'in-sync') { 'healthy' } elseif ($category -eq 'undetermined') { 'undetermined' } else { 'drifted' }
        })
    }

    if (Get-Command Get-PPMClientRenderDrift -ErrorAction SilentlyContinue) {
        foreach ($clientItem in @(Get-PPMClientRenderDrift -Inventory $Inventory -InventoryPath $InventoryPath -PrivateDirectory $PrivateDirectory)) { $items.Add($clientItem) }
    }

    $errors = @($items | Where-Object severity -eq 'error').Count
    $warnings = @($items | Where-Object severity -eq 'warning').Count
    return [ordered]@{
        schema_version = 1
        generated_at = [DateTime]::UtcNow.ToString('o')
        drifted = ($errors -gt 0 -or $warnings -gt 0)
        summary = [ordered]@{
            errors = $errors
            warnings = $warnings
            routes = @($Inventory.routes).Count
            client_targets = @(Get-PPMClientTargets -Inventory $Inventory).Count
        }
        items = @($items)
    }
}
