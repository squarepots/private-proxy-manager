[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')
. (Join-Path $repo 'lib\RouteSteward.Provider.ps1')
. (Join-Path $repo 'lib\RouteSteward.Agent.ps1')
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-core-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $state = Initialize-RSTPrivateState -PrivateDirectory $stage
    $inventoryPath = [string]$state.inventory_path
    $inventory = Read-RSTInventory -Path $inventoryPath

    Assert-True ($inventory.schema -eq 1) 'The first public inventory schema must be 1.'
    Assert-True (@($inventory.servers).Count -eq 0 -and @($inventory.links).Count -eq 0 -and @($inventory.routes).Count -eq 0) 'Clean inventory contains infrastructure assumptions.'
    Assert-True (@($inventory.providers).Count -eq 0 -and @($inventory.profiles).Count -eq 0 -and @($inventory.client_targets).Count -eq 0) 'Clean inventory contains provider/device/client assumptions.'
    Assert-True (-not $inventory.metadata.PSObject.Properties['model_version']) 'Inventory metadata contains an independent model-version axis.'

    $badSchema = $inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $badSchema.schema = 2
    $failed = $false
    try { $null = Assert-RSTInventory -Inventory $badSchema -PrivateDirectory $stage -SkipSecretCheck }
    catch { $failed = $_.Exception.Message -match 'schema must be 1' }
    Assert-True $failed 'Unsupported desired-state schema was accepted.'

    [IO.File]::WriteAllText((Join-Path $stage 'fixture.pem'), 'fixture', [Text.UTF8Encoding]::new($false))
    $serverContext = [pscustomobject][ordered]@{
        server_id = 'entry-a'; provider = 'example-compute'; region = 'example-region'; public_ipv4 = '192.0.2.10'; public_ipv6 = '2001:db8::10'; ssh_user = 'ubuntu'; ssh_key_path = (Join-Path $stage 'fixture.pem'); host_ownership = 'dedicated'
    }
    $null = Add-RSTServer -Inventory $inventory -InventoryPath $inventoryPath -Context $serverContext
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True ($inventory.servers[0].compute.driver -eq 'byo-ssh' -and $inventory.servers[0].compute.host_ownership -eq 'dedicated') 'Server does not declare its dedicated BYO compute contract.'

    foreach ($badUser in @('-oProxyCommand=bad','--help','bad@user','bad user',"bad`nuser",('a' * 33))) {
        Assert-True (-not (Test-RSTUnixUser $badUser)) "Unsafe SSH user '$badUser' passed the core validator."
    }
    foreach ($goodUser in @('ubuntu','root','user_1')) { Assert-True (Test-RSTUnixUser $goodUser) "Supported SSH user '$goodUser' was rejected." }

    $allocation = New-RSTLinkAllocation -Inventory $inventory
    Assert-True ($allocation.interface -eq 'wg-rst01' -and $allocation.listen_port -eq 51820 -and $allocation.subnet -eq '10.77.1.0/30') 'RST-native Link allocation is incorrect.'

    $routeContext = [pscustomobject][ordered]@{ route_id = 'direct-a'; display_name = 'Direct-A'; kind = 'direct'; entry_server = 'entry-a'; listen_port = 20000; port_hopping = '20000-20003' }
    $null = Add-RSTRoute -Inventory $inventory -InventoryPath $inventoryPath -Context $routeContext
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True ($inventory.routes[0].ingress.driver -eq 'hysteria2') 'Route does not declare the Hysteria2 ingress driver.'
    Assert-True ([int]$inventory.routes[0].port_hopping.start_port -eq 20000 -and [int]$inventory.routes[0].port_hopping.end_port -eq 20003) 'Route did not retain canonical bounded port hopping.'

    $profileContext = [pscustomobject][ordered]@{ profile_id = 'primary'; include_routes = @('direct-a'); include_providers = @() }
    $profile = Add-RSTProfile -Inventory $inventory -InventoryPath $inventoryPath -Context $profileContext
    Assert-True ([string]$profile.policy -eq '') 'A Profile silently selected a geographic policy.'
    $inventory = Read-RSTInventory -Path $inventoryPath
    $target = Add-RSTClientTarget -Inventory $inventory -InventoryPath $inventoryPath -Context ([pscustomobject][ordered]@{ target_id = 'desktop'; profile_id = 'primary'; renderer = 'mihomo' })
    Assert-True ($target.renderer -eq 'mihomo' -and $target.delivery -eq 'file') 'Explicit ClientTarget creation is incorrect.'

    $inventory = Read-RSTInventory -Path $inventoryPath
    $badListener = $inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $badListener.routes += ($badListener.routes[0] | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
    $badListener.routes[-1].id = 'duplicate-listener-route'
    $failed = $false
    try { $null = Assert-RSTInventory -Inventory $badListener -PrivateDirectory $stage -SkipSecretCheck }
    catch { $failed = $_.Exception.Message -match 'share listener' }
    Assert-True $failed 'Conflicting Hysteria2 listeners on one entry Server were accepted.'

    $badDriver = $inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $badDriver.routes[0].ingress.driver = 'unsupported'
    $failed = $false
    try { $null = Assert-RSTInventory -Inventory $badDriver -PrivateDirectory $stage -SkipSecretCheck }
    catch { $failed = $_.Exception.Message -match 'ingress\.driver=hysteria2' }
    Assert-True $failed 'Unsupported ingress driver was accepted.'

    $providerContext = [pscustomobject][ordered]@{ provider_id = 'upstream-a'; url = 'https://example.invalid/provider.yaml'; interval_seconds = 86400; enabled = $true }
    $null = Add-RSTProvider -Inventory $inventory -InventoryPath $inventoryPath -Context $providerContext
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True ($inventory.providers[0].source_type -eq 'mihomo-http' -and $inventory.providers[0].health_check -eq $false) 'Provider contract is incorrect.'
    Assert-True (-not $inventory.providers[0].PSObject.Properties['url']) 'Provider URL leaked into desired-state inventory.'

    if ($env:OS -ne 'Windows_NT') {
        Assert-True (Test-RSTPrivateAcl -Path $stage) 'POSIX private directory permissions are too broad.'
        Assert-True (Test-RSTPrivateAcl -Path $inventoryPath) 'POSIX inventory permissions are too broad.'
        Assert-True (Test-RSTPrivateAcl -Path (Join-Path $stage 'secrets\index.json')) 'POSIX secret index permissions are too broad.'
    }

    $managedRoute = Join-Path $stage 'managed-route'
    $null = & (Join-Path $repo 'scripts\New-ManagedRouteSecret.ps1') -RouteId test-managed -DisplayName Test-Managed -EntryIPv4 192.0.2.30 -EntryIPv6 2001:db8::30 -Port 9443 -SecretDirectory $managedRoute 6>&1
    Assert-True (Test-Path -LiteralPath (Join-Path $managedRoute 'server.key')) 'Local canonical Hysteria2 private key was not created.'
    $managedLink = Join-Path $stage 'managed-link\keys.json'
    $null = & (Join-Path $repo 'scripts\New-ManagedLinkSecret.ps1') -LinkId test-managed-link -OutputPath $managedLink 6>&1
    $keys = [IO.File]::ReadAllText($managedLink, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-True ($keys.entry.private_key -match '^[A-Za-z0-9+/]{43}=$' -and $keys.exit.public_key -match '^[A-Za-z0-9+/]{43}=$') 'Local canonical WireGuard keys are invalid.'
    Assert-True ($keys.entry.private_key -ne $keys.exit.private_key) 'Entry and exit WireGuard keys must differ.'

    Write-Host 'Public schema-1 core, validation, privacy, neutral bootstrap, and local secret generation tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
