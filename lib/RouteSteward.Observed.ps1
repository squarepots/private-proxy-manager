$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:RSTDriftCategories = @(
    'in-sync','service-missing','remote-config-mismatch','firewall-network-mismatch',
    'wireguard-link-mismatch','hysteria-listener-mismatch','certificate-mismatch',
    'egress-mismatch','undetermined'
)

function Get-RSTObservedPath {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    return Join-Path ([IO.Path]::GetFullPath($PrivateDirectory)) 'observed.json'
}

function Read-RSTObservedState {
    param([Parameter(Mandatory)][string]$PrivateDirectory, [switch]$AllowMissing)
    $path = Get-RSTObservedPath -PrivateDirectory $PrivateDirectory
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($AllowMissing) { return [pscustomobject][ordered]@{ schema = 1; generated_at = $null; servers = @(); links = @(); routes = @() } }
        throw 'Observed state was not found.'
    }
    $observed = Read-RSTJson -Path $path -Label 'Observed state'
    if ([int](Get-RSTOptional $observed 'schema' 0) -ne 1) { throw 'Observed state schema must be 1.' }
    return $observed
}

function Save-RSTObservedState {
    param([Parameter(Mandatory)]$Observed, [Parameter(Mandatory)][string]$PrivateDirectory)
    $Observed.generated_at = [DateTime]::UtcNow.ToString('o')
    Write-RSTJsonAtomic -Value $Observed -Path (Get-RSTObservedPath -PrivateDirectory $PrivateDirectory)
}

function Set-RSTObservedRoute {
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
    $route = Get-RSTRouteById -Inventory $Inventory -Id $RouteId
    if (-not $Category) {
        $Category = if ($Status -eq 'healthy') { 'in-sync' } elseif ($Status -eq 'mismatch') { 'egress-mismatch' } else { 'undetermined' }
    }
    if ($Category -notin $script:RSTDriftCategories) { $Category = 'undetermined' }

    $observed = Read-RSTObservedState -PrivateDirectory $PrivateDirectory -AllowMissing
    $routeMap = @{}
    foreach ($item in @(Get-RSTOptional $observed 'routes' @())) { $routeMap[[string]$item.id] = $item }
	$previousHealth = if ($routeMap.ContainsKey([string]$route.id)) { Get-RSTOptional $routeMap[[string]$route.id] 'health' } else { $null }
    $routeMap[[string]$route.id] = [pscustomobject][ordered]@{
        id = [string]$route.id
        audit_status = $Status
        category = $Category
        audited_at = [DateTime]::UtcNow.ToString('o')
        actual_egress_ipv4 = if ($ActualEgressIPv4) { $ActualEgressIPv4 } else { $null }
        hysteria_version = if ($HysteriaVersion) { $HysteriaVersion } else { $null }
        wireguard_version = if ($WireGuardVersion) { $WireGuardVersion } else { $null }
		health = $previousHealth
    }
    $validRouteIds = @($Inventory.routes | ForEach-Object { [string]$_.id })
    $observed.routes = @($routeMap.Keys | Where-Object { $validRouteIds -contains $_ } | Sort-Object | ForEach-Object { $routeMap[$_] })

    $serverMap = @{}
    foreach ($item in @(Get-RSTOptional $observed 'servers' @())) { $serverMap[[string]$item.id] = $item }
    foreach ($serverId in @([string]$route.entry_server, [string]$route.exit_server) | Sort-Object -Unique) {
        $serverMap[$serverId] = [pscustomobject][ordered]@{
            id = $serverId
            audit_status = if ($Status -eq 'healthy') { 'reachable' } elseif ($Category -eq 'service-missing') { 'unhealthy' } else { 'unknown' }
            audited_at = [DateTime]::UtcNow.ToString('o')
        }
    }
    $validServerIds = @($Inventory.servers | ForEach-Object { [string]$_.id })
    $observed.servers = @($serverMap.Keys | Where-Object { $validServerIds -contains $_ } | Sort-Object | ForEach-Object { $serverMap[$_] })

    if ([string]$route.kind -eq 'relay' -and (Get-RSTOptional $route 'link')) {
        $linkMap = @{}
        foreach ($item in @(Get-RSTOptional $observed 'links' @())) { $linkMap[[string]$item.id] = $item }
        $linkMap[[string]$route.link] = [pscustomobject][ordered]@{
            id = [string]$route.link
            audit_status = if ($Status -eq 'healthy') { 'healthy' } elseif ($Category -eq 'wireguard-link-mismatch') { 'mismatch' } else { 'unknown' }
            audited_at = [DateTime]::UtcNow.ToString('o')
        }
        $validLinkIds = @($Inventory.links | ForEach-Object { [string]$_.id })
        $observed.links = @($linkMap.Keys | Where-Object { $validLinkIds -contains $_ } | Sort-Object | ForEach-Object { $linkMap[$_] })
    }

    Save-RSTObservedState -Observed $observed -PrivateDirectory $PrivateDirectory
    return $routeMap[[string]$route.id]
}

function Get-RSTDriftSeverity {
    param([Parameter(Mandatory)][string]$Category)
    if ($Category -in @('in-sync','disabled')) { return 'info' }
    if ($Category -in @('never-audited','undetermined','client-render-stale')) { return 'warning' }
    return 'error'
}

function Get-RSTDriftReport {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [string]$InventoryPath
    )
    if (-not $InventoryPath) { $InventoryPath = Join-Path ([IO.Path]::GetFullPath($PrivateDirectory)) 'inventory.json' }
    $observed = Read-RSTObservedState -PrivateDirectory $PrivateDirectory -AllowMissing
    $observedByRoute = @{}
    foreach ($item in @(Get-RSTOptional $observed 'routes' @())) { $observedByRoute[[string]$item.id] = $item }
    $items = [Collections.Generic.List[object]]::new()

    foreach ($route in @($Inventory.routes | Sort-Object order)) {
        $enabled = (Get-RSTOptional $route 'enabled' $true) -ne $false
        $state = $observedByRoute[[string]$route.id]
        if (-not $enabled) {
            $items.Add([ordered]@{ id = [string]$route.id; category = 'disabled'; severity = 'info'; desired = 'disabled'; observed = if ($state) { [string](Get-RSTOptional $state 'audit_status' 'unknown') } else { 'not-observed' } })
            continue
        }
        if (-not $state) {
            $items.Add([ordered]@{ id = [string]$route.id; category = 'never-audited'; severity = 'warning'; desired = 'enabled'; observed = 'not-observed' })
            continue
        }

        $category = [string](Get-RSTOptional $state 'category')
        if (-not $category) {
            $auditStatus = [string](Get-RSTOptional $state 'audit_status' 'unknown')
            $category = if ($auditStatus -eq 'healthy') { 'in-sync' } elseif ($auditStatus -eq 'mismatch') { 'egress-mismatch' } else { 'undetermined' }
        }
        if ($category -notin $script:RSTDriftCategories) { $category = 'undetermined' }
        $items.Add([ordered]@{
            id = [string]$route.id
            category = $category
            severity = Get-RSTDriftSeverity -Category $category
            desired = 'enabled'
            observed = if ($category -eq 'in-sync') { 'healthy' } elseif ($category -eq 'undetermined') { 'undetermined' } else { 'drifted' }
        })
    }

    if (Get-Command Get-RSTClientRenderDrift -ErrorAction SilentlyContinue) {
        foreach ($clientItem in @(Get-RSTClientRenderDrift -Inventory $Inventory -InventoryPath $InventoryPath -PrivateDirectory $PrivateDirectory)) { $items.Add($clientItem) }
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
            client_targets = @(Get-RSTClientTargets -Inventory $Inventory).Count
        }
        items = @($items)
    }
}
