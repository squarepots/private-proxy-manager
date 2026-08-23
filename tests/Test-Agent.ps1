[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$agent = Join-Path $repo 'agent\route-steward-agent.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-agent-test-' + [Guid]::NewGuid().ToString('N'))
$recoveryTarget = Join-Path ([IO.Path]::GetTempPath()) ('rst-agent-recovery-target-' + [Guid]::NewGuid().ToString('N'))
$archiveFixture = Join-Path ([IO.Path]::GetTempPath()) ('rst-agent-recovery-fixture-' + [Guid]::NewGuid().ToString('N') + '.7z')
try {
    $bootstrap = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    Assert-True ($bootstrap.success -and $bootstrap.data.created) 'Clean agent bootstrap did not create private state.'
    Assert-True (Test-Path -LiteralPath (Join-Path $stage 'inventory.json')) 'Bootstrap did not create inventory.json.'
    Assert-True (Test-Path -LiteralPath (Join-Path $stage 'secrets\index.json')) 'Bootstrap did not create secret index.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $stage 'operator.json'))) 'Bootstrap created deprecated operator state.'
    Assert-True ($bootstrap.data.context.inventory_schema -eq 1) 'Clean bootstrap did not create public inventory schema 1.'
    Assert-True ($bootstrap.data.context.counts.providers -eq 0) 'Clean bootstrap unexpectedly requires a Provider.'
    Assert-True (@($bootstrap.data.context.profiles).Count -eq 0) 'Clean bootstrap must not assume a Profile or geographic policy.'
    Assert-True (@($bootstrap.data.context.client_targets).Count -eq 0) 'Clean bootstrap must not assume devices or client apps.'

    $legacyOperatorPath = Join-Path $stage 'operator.json'
    $legacyOperator = '{"schema":1,"mode":"steward"}'
    [IO.File]::WriteAllText($legacyOperatorPath, $legacyOperator, [Text.UTF8Encoding]::new($false))
    $bootstrapAgain = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    Assert-True (-not $bootstrapAgain.data.created) 'Bootstrap did not recognize complete existing state.'
    Assert-True ([IO.File]::ReadAllText($legacyOperatorPath, [Text.Encoding]::UTF8) -eq $legacyOperator) 'Deprecated operator state was changed instead of ignored.'

    $capabilities = & $agent capabilities -PrivateDirectory $stage | ConvertFrom-Json
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'add-server').Count -eq 1) 'Agent capability discovery is missing add-server.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'add-provider').Count -eq 1) 'Agent capability discovery is missing generic Provider lifecycle.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'add-profile').Count -eq 1) 'Profile lifecycle is missing from capability discovery.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'add-client-target').Count -eq 1) 'ClientTarget lifecycle is missing from capability discovery.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'rotate-subscription-token').authorization_class -eq 'credential-change') 'Target-scoped subscription rotation is not a guarded credential change.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'migrate-route').executor -eq 'workflow') 'Migration is not exposed as an overlap-first workflow.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'backup').executor -eq 'local-assisted') 'Backup does not declare the local secure-prompt boundary.'
    Assert-True (@($capabilities.data.capabilities | Where-Object id -eq 'recover').requires_local_secret_prompt) 'Recovery does not declare its local password prompt.'
    foreach ($removedCapability in 'set-mode','rotate-credential','delete-server','purchase-resource') {
        Assert-True (@($capabilities.data.capabilities | Where-Object id -eq $removedCapability).Count -eq 0) "Non-executable capability '$removedCapability' is still advertised."
    }
    $addServerCapability = @($capabilities.data.capabilities | Where-Object id -eq 'add-server')[0]
    Assert-True (@($addServerCapability.required_context | Where-Object name -eq 'host_ownership').Count -eq 1) 'add-server capability metadata does not declare host_ownership.'
    Assert-True (@($addServerCapability.required_context | Where-Object name -eq 'host_ownership')[0].type -eq 'dedicated') 'add-server capability metadata does not describe the dedicated-host type.'
    Assert-True (@($addServerCapability.effects) -contains 'update-local-desired-state') 'add-server capability metadata does not declare its effect.'
    Assert-True (@($capabilities.data.capabilities | Where-Object { -not $_.PSObject.Properties['required_context'] -or -not $_.PSObject.Properties['effects'] }).Count -eq 0) 'One or more operations omit required-context or effect metadata.'
    Assert-True ($capabilities.data.drivers.ingress[0].id -eq 'hysteria2' -and $capabilities.data.drivers.ingress[0].version -eq '2.9.3') 'Hysteria2 driver truth is missing or inconsistent.'
    Assert-True ($capabilities.data.drivers.links[0].id -eq 'wireguard-single-hop') 'WireGuard single-hop capability truth is missing.'
    Assert-True ($capabilities.data.drivers.compute[0].transport -eq 'ssh') 'BYO SSH compute capability truth is missing.'
    Assert-True (@($capabilities.data.drivers.renderers | Where-Object id -eq 'mihomo').Count -eq 1 -and @($capabilities.data.drivers.renderers | Where-Object id -eq 'shadowrocket').Count -eq 1) 'Client renderer capability truth is incomplete.'

    $blocked = & $agent preflight -PrivateDirectory $stage -Operation add-server | ConvertFrom-Json
    Assert-True (-not $blocked.data.ready -and $blocked.data.missing_context.Count -gt 0) 'Incomplete add-server context was not blocked.'

    $missingOwnershipContext = [ordered]@{ server_id = 'blocked-a'; public_ipv4 = '192.0.2.20'; ssh_user = 'ubuntu'; ssh_key_path = 'fixture.pem' } | ConvertTo-Json -Compress
    $missingOwnership = & $agent preflight -PrivateDirectory $stage -Operation add-server -ContextJson $missingOwnershipContext | ConvertFrom-Json
    Assert-True (-not $missingOwnership.data.ready -and @($missingOwnership.data.missing_context) -contains 'host-ownership') 'Add Server did not require explicit dedicated-host ownership.'
    foreach ($badUser in @('-oProxyCommand=bad','--help','bad@user','bad user',"bad`nuser",('a' * 33))) {
        $badContext = [ordered]@{ server_id = 'blocked-user'; public_ipv4 = '192.0.2.21'; ssh_user = $badUser; ssh_key_path = 'fixture.pem'; host_ownership = 'dedicated' } | ConvertTo-Json -Compress
        $badPreflight = & $agent preflight -PrivateDirectory $stage -Operation add-server -ContextJson $badContext | ConvertFrom-Json
        Assert-True (-not $badPreflight.data.ready -and @($badPreflight.data.conflicts) -contains 'ssh-user-invalid') "Unsafe SSH user '$badUser' passed preflight."
    }

    $keyPath = Join-Path $stage 'fixture.pem'
    [IO.File]::WriteAllText($keyPath, 'fixture', [Text.UTF8Encoding]::new($false))
    $serverContext = [ordered]@{
        server_id = 'entry-a'
        provider = 'example-compute'
        region = 'example-region'
        public_ipv4 = '192.0.2.10'
        public_ipv6 = '2001:db8::10'
        ssh_user = 'ubuntu'
        ssh_key_path = $keyPath
        host_ownership = 'dedicated'
    } | ConvertTo-Json -Compress
    $addServer = & $agent execute -PrivateDirectory $stage -Operation add-server -ContextJson $serverContext | ConvertFrom-Json
    Assert-True ($addServer.success -and $addServer.data.result.id -eq 'entry-a') 'Structured add-server failed.'
    Assert-True ($addServer.data.result.compute_driver -eq 'byo-ssh' -and $addServer.data.result.host_ownership -eq 'dedicated' -and -not $addServer.data.result.remote_changed) 'add-server did not preserve explicit dedicated compute/local-only semantics.'

    $routeContext = [ordered]@{ route_id = 'direct-a'; display_name = 'Direct-A'; kind = 'direct'; entry_server = 'entry-a'; listen_port = 443 } | ConvertTo-Json -Compress
    $addRoute = & $agent execute -PrivateDirectory $stage -Operation add-route -ContextJson $routeContext | ConvertFrom-Json
    Assert-True ($addRoute.success -and $addRoute.data.result.id -eq 'direct-a') 'Structured add-route failed.'
    Assert-True ($addRoute.data.result.ingress_driver -eq 'hysteria2' -and -not $addRoute.data.result.enabled) 'A new Route did not preserve explicit ingress driver/pending semantics.'

    $profileContext = [ordered]@{ profile_id = 'primary'; include_routes = @('direct-a'); include_providers = @() } | ConvertTo-Json -Compress
    $addProfile = & $agent execute -PrivateDirectory $stage -Operation add-profile -ContextJson $profileContext | ConvertFrom-Json
    Assert-True ($addProfile.success -and $addProfile.data.result.id -eq 'primary') 'Explicit Profile creation failed.'
    $targetContext = [ordered]@{ target_id = 'desktop'; profile_id = 'primary'; renderer = 'mihomo' } | ConvertTo-Json -Compress
    $addTarget = & $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $targetContext | ConvertFrom-Json
    Assert-True ($addTarget.success -and $addTarget.data.result.renderer -eq 'mihomo') 'Explicit ClientTarget creation failed.'

    $deployPreflight = & $agent preflight -PrivateDirectory $stage -Operation deploy-route -Target direct-a | ConvertFrom-Json
    Assert-True ($deployPreflight.data.ready) 'A fully prepared local Route did not pass deploy preflight.'

    $context = & $agent context -PrivateDirectory $stage | ConvertFrom-Json
    $contextText = $context | ConvertTo-Json -Depth 20
    Assert-True ($context.data.inventory_schema -eq 1 -and -not $context.data.PSObject.Properties['mode']) 'Sanitized context did not preserve schema state or still exposed a deprecated mode.'
    Assert-True (-not ($contextText -match '192\.0\.2\.10|fixture\.pem|2001:db8')) 'Agent context leaked private infrastructure data.'

    [IO.File]::WriteAllText($archiveFixture, 'fixture-only-for-preflight', [Text.UTF8Encoding]::new($false))
    $recoveryContext = [ordered]@{ archive_path = $archiveFixture } | ConvertTo-Json -Compress
    $recoverPreflight = & $agent preflight -PrivateDirectory $recoveryTarget -Operation recover -ContextJson $recoveryContext | ConvertFrom-Json
    Assert-True ($recoverPreflight.success -and $recoverPreflight.data.ready) 'Recovery preflight cannot operate when canonical private state is absent.'
    Assert-True ($recoverPreflight.data.executor -eq 'local-assisted' -and $recoverPreflight.data.requires_local_secret_prompt) 'Recovery preflight does not preserve the local secret prompt boundary.'
    $recoverExecute = & $agent execute -PrivateDirectory $recoveryTarget -Operation recover -ContextJson $recoveryContext | ConvertFrom-Json
    Assert-True (-not $recoverExecute.success -and $recoverExecute.code -eq 'local-assistance-required') 'Agent recovery incorrectly pretended to complete through a non-interactive model channel.'
    Assert-True ($recoverExecute.data.result.repository_script -eq 'scripts/Restore-RecoveryArchive.ps1') 'Agent recovery did not delegate to the repository-owned secure restore workflow.'
    $global:LASTEXITCODE = 0

    Write-Host 'Agent bootstrap, capability discovery, preflight, authorization, schema, legacy operator tolerance, and assisted recovery tests passed.'
}
finally {
    foreach ($path in @($stage, $recoveryTarget)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force } }
    if (Test-Path -LiteralPath $archiveFixture) { Remove-Item -LiteralPath $archiveFixture -Force }
}
