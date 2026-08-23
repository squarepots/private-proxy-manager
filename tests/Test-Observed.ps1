[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')
. (Join-Path $repo 'lib\RouteSteward.ClientState.ps1')
. (Join-Path $repo 'lib\RouteSteward.Observed.ps1')
$agent = Join-Path $repo 'agent\route-steward-agent.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-observed-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    $keyPath = Join-Path $stage 'fixture.pem'
    [IO.File]::WriteAllText($keyPath, 'fixture', [Text.UTF8Encoding]::new($false))
    $serverContext = [ordered]@{ server_id = 'entry-a'; public_ipv4 = '192.0.2.44'; ssh_user = 'ubuntu'; ssh_key_path = $keyPath; host_ownership = 'dedicated' } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-server -ContextJson $serverContext | ConvertFrom-Json
    $routeContext = [ordered]@{ route_id = 'route-a'; display_name = 'Route-A'; kind = 'direct'; entry_server = 'entry-a'; listen_port = 443 } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-route -ContextJson $routeContext | ConvertFrom-Json
    $profileContext = [ordered]@{ profile_id = 'primary'; include_routes = @('route-a'); include_providers = @() } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-profile -ContextJson $profileContext | ConvertFrom-Json
    foreach ($target in @(
        [ordered]@{ target_id = 'desktop'; profile_id = 'primary'; renderer = 'mihomo' },
        [ordered]@{ target_id = 'mobile'; profile_id = 'primary'; renderer = 'shadowrocket'; delivery = 'nodes' }
    )) { $null = & $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson ($target | ConvertTo-Json -Compress) | ConvertFrom-Json }

    $inventoryPath = Join-Path $stage 'inventory.json'
    $inventory = Read-RSTInventory -Path $inventoryPath
    $inventory.routes[0].enabled = $true
    $inventory.routes[0].state = 'deployed'
    Save-RSTInventory -Inventory $inventory -InventoryPath $inventoryPath

    $before = & $agent drift -PrivateDirectory $stage | ConvertFrom-Json
    $routeBefore = @($before.data.items | Where-Object id -eq 'route-a')[0]
    Assert-True ($before.data.drifted -and $routeBefore.category -eq 'never-audited') 'An enabled never-audited Route was not surfaced as drift.'
    Assert-True (@($before.data.items | Where-Object category -eq 'client-render-stale').Count -eq 2) 'Missing explicit ClientTarget renders were not surfaced as stale.'

    $inventory = Read-RSTInventory -Path $inventoryPath
    foreach ($case in @(
        @{ Category = 'service-missing'; Status = 'mismatch' },
        @{ Category = 'remote-config-mismatch'; Status = 'mismatch' },
        @{ Category = 'firewall-network-mismatch'; Status = 'mismatch' },
        @{ Category = 'wireguard-link-mismatch'; Status = 'mismatch' },
        @{ Category = 'hysteria-listener-mismatch'; Status = 'mismatch' },
        @{ Category = 'certificate-mismatch'; Status = 'mismatch' },
        @{ Category = 'egress-mismatch'; Status = 'mismatch' },
        @{ Category = 'undetermined'; Status = 'undetermined' }
    )) {
        $null = Set-RSTObservedRoute -Inventory $inventory -PrivateDirectory $stage -RouteId route-a -Status $case.Status -Category $case.Category -ActualEgressIPv4 '192.0.2.44' -HysteriaVersion 'v-test'
        $report = & $agent drift -PrivateDirectory $stage | ConvertFrom-Json
        $routeItem = @($report.data.items | Where-Object id -eq 'route-a')[0]
        Assert-True ($routeItem.category -eq $case.Category) "Typed drift category '$($case.Category)' was not preserved through the sanitized agent surface."
        if ($case.Category -eq 'undetermined') { Assert-True ($routeItem.severity -eq 'warning') 'Undetermined drift must remain a warning rather than false certainty.' }
        else { Assert-True ($routeItem.severity -eq 'error') "Typed drift '$($case.Category)' did not preserve error severity." }
    }

    $null = Set-RSTObservedRoute -Inventory $inventory -PrivateDirectory $stage -RouteId route-a -Status healthy -Category in-sync -ActualEgressIPv4 '192.0.2.44' -HysteriaVersion 'v-test'
    $healthyWithStaleClients = & $agent drift -PrivateDirectory $stage | ConvertFrom-Json
    $healthyRoute = @($healthyWithStaleClients.data.items | Where-Object id -eq 'route-a')[0]
    Assert-True ($healthyRoute.category -eq 'in-sync' -and $healthyRoute.severity -eq 'info') 'Healthy observed Route was not reported in sync.'
    Assert-True ($healthyWithStaleClients.data.drifted) 'Stale ClientTargets were incorrectly hidden by a healthy Route.'

    $render = & $agent execute -PrivateDirectory $stage -Operation render-client | ConvertFrom-Json
    Assert-True ($render.success -and @($render.data.result.outputs).Count -eq 2) 'Agent did not render both explicit ClientTargets.'
    $renderText = $render | ConvertTo-Json -Depth 20
    Assert-True (-not ($renderText -match [regex]::Escape($stage)) -and -not ($renderText -match '(?i)[a-z]:\\')) 'Agent render output leaked an absolute local path.'
    Assert-True (@($render.data.result.outputs | Where-Object { $_.PSObject.Properties['path'] }).Count -eq 0) 'Agent render output retained the internal path field.'
    Assert-True (@($render.data.result.outputs | Where-Object { $_.artifact.relative_path -notmatch '^<private>/delivery/[^/\\]+$' }).Count -eq 0) 'Agent render output did not use the sanitized artifact shape.'
    Assert-True (Test-Path -LiteralPath (Join-Path $stage 'delivery\client-render-manifest.json')) 'Successful Agent rendering did not record the private hash-only render manifest.'

    $after = & $agent drift -PrivateDirectory $stage | ConvertFrom-Json
    Assert-True (-not $after.data.drifted) 'Healthy Route plus current ClientTarget renders was not reported in sync.'
    Assert-True (@($after.data.items | Where-Object category -eq 'client-render-stale').Count -eq 0) 'Current ClientTarget renders remained falsely stale.'
    $agentText = $after | ConvertTo-Json -Depth 20
    Assert-True (-not ($agentText -match '192\.0\.2\.44|v-test|fixture\.pem')) 'Drift output leaked local observed evidence.'

    $observed = Read-RSTObservedState -PrivateDirectory $stage
    Assert-True ($observed.routes[0].actual_egress_ipv4 -eq '192.0.2.44') 'Local observed state did not preserve audit evidence.'
    Write-Host 'Typed route drift, explicit ClientTarget render drift, and sanitized evidence tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
