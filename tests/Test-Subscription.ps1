[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\PrivateProxyManager.Core.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Model.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Subscription.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.SubscriptionTargets.ps1')
$agent = Join-Path $repo 'agent\ppm-agent.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('ppm-subscription-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    $keyPath = Join-Path $stage 'fixture.pem'
    [IO.File]::WriteAllText($keyPath, 'fixture', [Text.UTF8Encoding]::new($false))
    $serverContext = [ordered]@{ server_id = 'entry-a'; public_ipv4 = '192.0.2.80'; public_ipv6 = '2001:db8::80'; ssh_user = 'ubuntu'; ssh_key_path = $keyPath; host_ownership = 'dedicated' } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-server -ContextJson $serverContext | ConvertFrom-Json
    $routeContext = [ordered]@{ route_id = 'private-route'; display_name = 'Private-Route'; kind = 'direct'; entry_server = 'entry-a'; listen_port = 443 } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-route -ContextJson $routeContext | ConvertFrom-Json
    $profileContext = [ordered]@{ profile_id = 'primary'; include_routes = @('private-route'); include_providers = @() } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-profile -ContextJson $profileContext | ConvertFrom-Json
    foreach ($target in @(
        [ordered]@{ target_id = 'desktop'; profile_id = 'primary'; renderer = 'mihomo' },
        [ordered]@{ target_id = 'mobile'; profile_id = 'primary'; renderer = 'shadowrocket'; delivery = 'nodes' }
    )) { $null = & $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson ($target | ConvertTo-Json -Compress) | ConvertFrom-Json }

    $inventoryPath = Join-Path $stage 'inventory.json'
    $inventory = Read-PPMInventory -Path $inventoryPath
    $inventory.routes[0].enabled = $true
    $inventory.routes[0].state = 'deployed'
    Save-PPMInventory -Inventory $inventory -InventoryPath $inventoryPath

    $blocked = & $agent preflight -PrivateDirectory $stage -Operation publish-subscription -Target mobile | ConvertFrom-Json
    Assert-True (-not $blocked.data.ready) 'Uninitialized subscription publication passed without delivery context.'
    Assert-True (@($blocked.data.missing_context) -contains 'worker-name' -and @($blocked.data.missing_context) -contains 'host') 'Subscription context gate did not ask for Worker identity and host.'

    $inventory = Read-PPMInventory -Path $inventoryPath
    $state = Initialize-PPMClientSubscriptionState -Inventory $inventory -InventoryPath $inventoryPath -TargetId mobile -WorkerName ppm-subscription -HostName subscription.example.invalid
    Assert-True ($state.WorkerName -eq 'ppm-subscription' -and $state.Host -eq 'subscription.example.invalid') 'Generic subscription identity was not persisted.'
    Assert-True ($state.Token -match '^[A-Za-z0-9_-]{43}$') 'Subscription token is not a 256-bit base64url token.'
    $inventory = Read-PPMInventory -Path $inventoryPath
    $mobile = Get-PPMClientTargetById -Inventory $inventory -Id mobile
    $desktop = Get-PPMClientTargetById -Inventory $inventory -Id desktop
    Assert-True ([string]$mobile.subscription_secret_ref -eq 'subscription:mobile') 'Subscription credential was not scoped to the mobile ClientTarget.'
    Assert-True (-not (Get-PPMOptional $desktop 'subscription_secret_ref')) 'Subscription credential leaked onto an unrelated ClientTarget.'
    Assert-True ([string]$mobile.delivery -eq 'subscription') 'Shadowrocket ClientTarget did not switch to subscription delivery.'

    $secondTargetContext = [ordered]@{ target_id = 'tablet'; profile_id = 'primary'; renderer = 'shadowrocket'; delivery = 'nodes' } | ConvertTo-Json -Compress
    $secondTarget = & $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $secondTargetContext | ConvertFrom-Json
    Assert-True ($secondTarget.success -and $secondTarget.data.result.renderer -eq 'shadowrocket') 'Second Shadowrocket ClientTarget could not be added.'
    $inventory = Read-PPMInventory -Path $inventoryPath
    $collisionBlocked = $false
    try { $null = Initialize-PPMClientSubscriptionState -Inventory $inventory -InventoryPath $inventoryPath -TargetId tablet -WorkerName ppm-subscription -HostName subscription.example.invalid }
    catch { $collisionBlocked = $true }
    Assert-True $collisionBlocked 'Two subscription-backed ClientTargets were allowed to share one Worker/host identity.'
    $tablet = Get-PPMClientTargetById -Inventory (Read-PPMInventory -Path $inventoryPath) -Id tablet
    Assert-True (-not (Get-PPMOptional $tablet 'subscription_secret_ref')) 'Failed subscription identity allocation left partial target credential state.'

    $ready = & $agent preflight -PrivateDirectory $stage -Operation publish-subscription -Target mobile | ConvertFrom-Json
    Assert-True $ready.data.ready 'Initialized ClientTarget subscription publication did not pass the context gate.'

    $bodyPath = Join-Path $stage 'body.txt'
    $bodyResult = & (Join-Path $repo 'client\Export-ShadowrocketSubscription.ps1') -InventoryPath $inventoryPath -ClientTargetId mobile -OutputPath $bodyPath | ConvertFrom-Json
    Assert-True ($bodyResult.node_count -eq 2 -and $bodyResult.client_target -eq 'mobile') 'Direct Route did not export both Shadowrocket nodes for the requested ClientTarget.'
    $encoded = [IO.File]::ReadAllText($bodyPath, [Text.Encoding]::UTF8)
    $plain = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    Assert-True ($plain -match 'hysteria2://' -and $plain -match 'Private-Route-HY2-v4') 'Subscription body does not contain complete private node URIs.'

    Assert-True ((Assert-PPMSubscriptionBodySize -Body ('a' * 5120)) -eq 5120) 'A 5120-byte subscription payload was rejected.'
    Assert-True ((Assert-PPMSubscriptionBodySize -Body ('é' * 2560)) -eq 5120) 'A 5120-byte multibyte UTF-8 subscription payload was miscounted.'
    foreach ($oversizeBody in @(('a' * 5121), (('é' * 2560) + 'a'))) {
        $oversizeBlocked = $false
        try { $null = Assert-PPMSubscriptionBodySize -Body $oversizeBody }
        catch { $oversizeBlocked = $_.Exception.Message -eq 'subscription-payload-too-large' }
        Assert-True $oversizeBlocked 'A subscription payload larger than 5120 UTF-8 bytes was not rejected with the stable error code.'
    }

    $null = & $agent mode -PrivateDirectory $stage -Mode steward | ConvertFrom-Json
    $rotationBlocked = & $agent preflight -PrivateDirectory $stage -Operation rotate-subscription-token -Target mobile | ConvertFrom-Json
    Assert-True (-not $rotationBlocked.data.ready -and -not $rotationBlocked.data.authorized) 'Steward Mode incorrectly authorized subscription token rotation.'
    Assert-True ($rotationBlocked.data.authorization_class -eq 'credential-change') 'Subscription token rotation is not classified as a credential change.'
    $rotationReady = & $agent preflight -PrivateDirectory $stage -Operation rotate-subscription-token -Target mobile -Approved | ConvertFrom-Json
    Assert-True ($rotationReady.data.ready -and $rotationReady.data.authorized) 'Explicitly authorized target-scoped token rotation did not pass preflight.'
    Assert-True (@($rotationReady.data.expected_effects) -contains 'leave-route-and-other-client-credentials-unchanged') 'Rotation blast-radius contract is missing.'

    $context = & $agent context -PrivateDirectory $stage | ConvertFrom-Json
    $agentText = $context | ConvertTo-Json -Depth 20
    Assert-True (-not ($agentText.Contains($state.Token) -or $agentText -match 'subscription\.example\.invalid|192\.0\.2\.80')) 'Agent context leaked subscription or endpoint secrets.'
    Write-Host 'Explicit ClientTarget-scoped subscription state, isolated delivery identity, export, redaction, and rotation authorization tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
