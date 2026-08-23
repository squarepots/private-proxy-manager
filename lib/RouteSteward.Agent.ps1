$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'RouteSteward.Version.ps1')

function Get-RSTCapabilityCatalog {
    $catalog = @(
        [ordered]@{ id = 'status'; state = 'supported'; executor = 'agent'; mutation = $false; authorization_class = 'read-only'; description = 'Read sanitized local state.' },
        [ordered]@{ id = 'drift'; state = 'supported'; executor = 'agent'; mutation = $false; authorization_class = 'read-only'; description = 'Compare desired routes and ClientTarget renders with sanitized observed state.' },
        [ordered]@{ id = 'audit'; state = 'supported'; executor = 'core'; mutation = $false; authorization_class = 'read-only'; description = 'Compare one supported remote Route with desired state without changing it.' },
        [ordered]@{ id = 'bootstrap'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Create clean local private state.' },
        [ordered]@{ id = 'add-server'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Add a BYO SSH Server to desired state without connecting to it.' },
        [ordered]@{ id = 'add-link'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Allocate one WireGuard Link and local canonical keys.' },
        [ordered]@{ id = 'add-route'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Add a Hysteria2 direct or relay Route and local canonical credentials.' },
        [ordered]@{ id = 'add-provider'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Add an optional generic upstream Provider and keep its URL in local secret storage.' },
        [ordered]@{ id = 'update-provider'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Update an existing optional Provider without exposing its URL through agent status.' },
        [ordered]@{ id = 'remove-provider'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Remove an unreferenced Provider and its local URL secret.' },
        [ordered]@{ id = 'add-profile'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Add a reusable route/provider/policy selection Profile.' },
        [ordered]@{ id = 'update-profile'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Update a Profile selection without changing renderer identity.' },
        [ordered]@{ id = 'remove-profile'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Remove a Profile only when no ClientTarget references it.' },
        [ordered]@{ id = 'add-client-target'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Add a renderer-backed ClientTarget that references a reusable Profile.' },
        [ordered]@{ id = 'update-client-target'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Update ClientTarget delivery/profile selection within the supported renderer contract.' },
        [ordered]@{ id = 'remove-client-target'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'local-write'; description = 'Remove a ClientTarget after any target-scoped subscription state is revoked.' },
        [ordered]@{ id = 'deploy-route'; state = 'supported'; executor = 'core'; mutation = $true; authorization_class = 'remote-write'; description = 'Deploy one existing desired Route.' },
        [ordered]@{ id = 'render-client'; state = 'supported'; executor = 'core'; mutation = $true; authorization_class = 'local-write'; description = 'Render supported client artifacts from canonical state.' },
        [ordered]@{ id = 'publish-subscription'; state = 'supported'; executor = 'core'; mutation = $true; authorization_class = 'external-publication'; description = 'Publish one private ClientTarget subscription payload.' },
        [ordered]@{ id = 'rotate-subscription-token'; state = 'supported'; executor = 'agent'; mutation = $true; authorization_class = 'credential-change'; description = 'Rotate only one ClientTarget subscription bearer token after explicit current authorization.' },
        [ordered]@{ id = 'migrate-route'; state = 'supported'; executor = 'workflow'; mutation = $true; authorization_class = 'remote-write'; description = 'Overlap-first workflow composed from add/deploy/audit operations; old capacity is not retired automatically.' },
        [ordered]@{ id = 'backup'; state = 'supported'; executor = 'local-assisted'; mutation = $true; authorization_class = 'local-write'; requires_local_secret_prompt = $true; description = 'Create an encrypted recovery archive through a local 7-Zip password prompt that is never sent through the model/MCP stream.' },
        [ordered]@{ id = 'recover'; state = 'supported'; executor = 'local-assisted'; mutation = $true; authorization_class = 'local-write'; requires_local_secret_prompt = $true; description = 'Restore canonical private state through the repository-owned local recovery workflow and secure 7-Zip prompt.' }
    )
    $requiredContext = @{
        'add-server' = @(
            [ordered]@{ name = 'server_id'; type = 'stable-id'; required = $true },
            [ordered]@{ name = 'public_ipv4'; type = 'ipv4'; required = $true },
            [ordered]@{ name = 'ssh_user'; type = 'unix-user'; required = $true },
            [ordered]@{ name = 'ssh_key_path'; type = 'local-file-path'; required = $true },
            [ordered]@{ name = 'host_ownership'; type = 'dedicated'; required = $true }
        )
        'add-link' = @([ordered]@{ name = 'link_id'; type = 'stable-id'; required = $true },[ordered]@{ name = 'entry_server'; type = 'server-id'; required = $true },[ordered]@{ name = 'exit_server'; type = 'server-id'; required = $true })
        'add-route' = @([ordered]@{ name = 'route_id'; type = 'stable-id'; required = $true },[ordered]@{ name = 'kind'; type = 'direct|relay'; required = $true },[ordered]@{ name = 'entry_server'; type = 'server-id'; required = $true })
        'add-provider' = @([ordered]@{ name = 'provider_id'; type = 'stable-id'; required = $true },[ordered]@{ name = 'url'; type = 'http-url'; required = $true })
        'update-provider' = @([ordered]@{ name = 'target'; type = 'provider-id'; required = $true; source = 'argument' })
        'remove-provider' = @([ordered]@{ name = 'target'; type = 'provider-id'; required = $true; source = 'argument' })
        'add-profile' = @([ordered]@{ name = 'profile_id'; type = 'stable-id'; required = $true })
        'update-profile' = @([ordered]@{ name = 'target'; type = 'profile-id'; required = $true; source = 'argument' })
        'remove-profile' = @([ordered]@{ name = 'target'; type = 'profile-id'; required = $true; source = 'argument' })
        'add-client-target' = @([ordered]@{ name = 'target_id'; type = 'stable-id'; required = $true },[ordered]@{ name = 'profile_id'; type = 'profile-id'; required = $true },[ordered]@{ name = 'renderer'; type = 'mihomo|shadowrocket'; required = $true })
        'update-client-target' = @([ordered]@{ name = 'target'; type = 'client-target-id'; required = $true; source = 'argument' })
        'remove-client-target' = @([ordered]@{ name = 'target'; type = 'client-target-id'; required = $true; source = 'argument' })
        'audit' = @([ordered]@{ name = 'target'; type = 'route-id'; required = $true; source = 'argument' })
        'deploy-route' = @([ordered]@{ name = 'target'; type = 'route-id'; required = $true; source = 'argument' })
        'render-client' = @([ordered]@{ name = 'target'; type = 'client-target-id'; required = $false; source = 'argument' })
        'publish-subscription' = @([ordered]@{ name = 'target'; type = 'client-target-id'; required = $true; source = 'argument' },[ordered]@{ name = 'worker_name'; type = 'worker-name'; required = $false; when = 'subscription state is absent' },[ordered]@{ name = 'host'; type = 'hostname'; required = $false; when = 'subscription state is absent' })
        'rotate-subscription-token' = @([ordered]@{ name = 'target'; type = 'client-target-id'; required = $true; source = 'argument' })
        'migrate-route' = @([ordered]@{ name = 'target'; type = 'route-id'; required = $true; source = 'argument' },[ordered]@{ name = 'replacement_server_id'; type = 'server-id'; required = $true })
        'recover' = @([ordered]@{ name = 'archive_path'; type = 'local-file-path'; required = $true })
    }
    $declaredEffects = @{
        status = @('read-sanitized-local-state'); drift = @('read-sanitized-local-and-observed-state'); audit = @('read-remote-supported-state'); bootstrap = @('create-local-private-state'); 'add-server' = @('update-local-desired-state'); 'add-link' = @('allocate-local-link-and-keys'); 'add-route' = @('allocate-local-route-and-credentials'); 'add-provider' = @('store-provider-url-as-local-secret'); 'update-provider' = @('update-local-provider'); 'remove-provider' = @('remove-local-provider-and-secret'); 'add-profile' = @('update-local-profile'); 'update-profile' = @('update-local-profile'); 'remove-profile' = @('remove-local-profile'); 'add-client-target' = @('update-local-client-target'); 'update-client-target' = @('update-local-client-target'); 'remove-client-target' = @('remove-local-client-target'); 'deploy-route' = @('mutate-supported-dedicated-hosts','render-private-client-artifacts'); 'render-client' = @('write-private-client-artifacts'); 'publish-subscription' = @('publish-private-subscription-payload'); 'rotate-subscription-token' = @('rotate-target-subscription-token'); 'migrate-route' = @('create-and-validate-overlap'); backup = @('write-encrypted-local-recovery-archive'); recover = @('restore-local-canonical-state')
    }
    foreach ($capability in $catalog) {
        $id = [string]$capability.id
        $capability.required_context = if ($requiredContext.ContainsKey($id)) { @($requiredContext[$id]) } else { @() }
        $capability.effects = if ($declaredEffects.ContainsKey($id)) { @($declaredEffects[$id]) } else { @() }
    }
    return $catalog
}

function Get-RSTCapabilityById {
    param([Parameter(Mandatory)][string]$Id)
    $matches = @(Get-RSTCapabilityCatalog | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Unsupported RST operation '$Id'." }
    return $matches[0]
}

function Get-RSTDriverCapabilities {
    return [ordered]@{
        schema_version = 1
        product_version = Get-RSTProductVersion
        compute = @([ordered]@{ id = 'byo-ssh-ubuntu-24.04-amd64'; state = 'supported'; provisioning = 'bring-your-own'; transport = 'ssh'; package_manager = 'apt'; architecture = 'amd64'; operating_system = 'ubuntu-24.04'; host_ownership = 'dedicated' })
        ingress = @([ordered]@{ id = 'hysteria2'; state = 'supported'; version = '2.9.3'; transport = 'udp'; address_families = @('ipv4','ipv6'); credential_model = 'local-canonical-pinned-tls' })
        links = @([ordered]@{ id = 'wireguard-single-hop'; state = 'supported'; hops = 1; address_family = 'ipv4' })
        providers = @([ordered]@{ id = 'mihomo-http-provider'; state = 'supported'; optional = $true; schemes = @('https','http'); health_check = $false })
        renderers = @(
            [ordered]@{ id = 'mihomo'; state = 'supported'; clients = @('Clash Verge-compatible Mihomo clients') },
            [ordered]@{ id = 'shadowrocket'; state = 'supported'; delivery = @('node-import','private-subscription') }
        )
        subscription_delivery = @([ordered]@{ id = 'cloudflare-worker'; state = 'supported'; optional = $true; role = 'private-config-delivery-only' })
    }
}

function Read-RSTStateInventory {
    param([Parameter(Mandatory)][string]$Path, [switch]$SkipSecretCheck)
    return Read-RSTInventory -Path $Path -SkipSecretCheck:$SkipSecretCheck
}

function Initialize-RSTPrivateState {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    $privatePath = [IO.Path]::GetFullPath($PrivateDirectory)
    $inventoryPath = Join-Path $privatePath 'inventory.json'
    $secretIndexPath = Join-Path $privatePath 'secrets\index.json'
    $observedPath = Join-Path $privatePath 'observed.json'
    $knownPaths = @($inventoryPath, $secretIndexPath, $observedPath)
    $existing = @($knownPaths | Where-Object { Test-Path -LiteralPath $_ })

    if ($existing.Count -gt 0) {
        if ((Test-Path -LiteralPath $inventoryPath -PathType Leaf) -and (Test-Path -LiteralPath $secretIndexPath -PathType Leaf)) {
            $inventory = Read-RSTStateInventory -Path $inventoryPath
            if (-not (Test-Path -LiteralPath $observedPath -PathType Leaf)) {
                Write-RSTJsonAtomic -Value ([ordered]@{ schema = 1; generated_at = $null; servers = @(); links = @(); routes = @() }) -Path $observedPath
            }
            return [pscustomobject]@{ created = $false; inventory_path = $inventoryPath; inventory = $inventory }
        }
        throw 'Private state is partially initialized. Refusing to overwrite or guess how to repair it.'
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $privatePath 'secrets') | Out-Null
    Protect-RSTPath -Path $privatePath -Directory
    Protect-RSTPath -Path (Join-Path $privatePath 'secrets') -Directory
    $inventory = New-RSTCleanInventory -PrivateDirectory $privatePath
    Write-RSTJsonAtomic -Value ([ordered]@{ schema = 1; refs = [ordered]@{} }) -Path $secretIndexPath
    Write-RSTJsonAtomic -Value $inventory -Path $inventoryPath
    Write-RSTJsonAtomic -Value ([ordered]@{ schema = 1; generated_at = $null; servers = @(); links = @(); routes = @() }) -Path $observedPath
    $inventory = Read-RSTInventory -Path $inventoryPath
    return [pscustomobject]@{ created = $true; inventory_path = $inventoryPath; inventory = $inventory }
}

function Get-RSTSanitizedContext {
    param([Parameter(Mandatory)]$Inventory)
    $enabledRoutes = @(@(Get-RSTOptional $Inventory 'routes' @()) | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false })
    $enabledProviders = @(@(Get-RSTOptional $Inventory 'providers' @()) | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false })
    $profiles = @(Get-RSTOptional $Inventory 'profiles' @())
    $targets = @(Get-RSTClientTargets -Inventory $Inventory)
    return [ordered]@{
        schema_version = 1
        inventory_schema = [int]$Inventory.schema
        counts = [ordered]@{
            servers = @(Get-RSTOptional $Inventory 'servers' @()).Count
            links = @(Get-RSTOptional $Inventory 'links' @()).Count
            routes = @(Get-RSTOptional $Inventory 'routes' @()).Count
            enabled_routes = $enabledRoutes.Count
            providers = @(Get-RSTOptional $Inventory 'providers' @()).Count
            enabled_providers = $enabledProviders.Count
            profiles = $profiles.Count
            client_targets = $targets.Count
        }
        profiles = @($profiles | ForEach-Object { [ordered]@{ id = [string]$_.id; policy = [string](Get-RSTOptional $_ 'policy') } })
        client_targets = @($targets | ForEach-Object { [ordered]@{ id = [string]$_.id; profile = [string](Get-RSTOptional $_ 'profile'); renderer = [string](Get-RSTOptional $_ 'renderer'); delivery = [string](Get-RSTOptional $_ 'delivery') } })
        supported_operations = @(Get-RSTCapabilityCatalog | ForEach-Object { [ordered]@{ id = $_.id; state = $_.state; authorization_class = $_.authorization_class } })
    }
}

function Get-RSTTargetRoute {
    param($Inventory, [AllowNull()][string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    return @($Inventory.routes | Where-Object { $_.id -eq $Target -or $_.display_name -eq $Target }) | Select-Object -First 1
}

function Get-RSTTargetServer {
    param($Inventory, [AllowNull()][string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    return @($Inventory.servers | Where-Object { $_.id -eq $Target }) | Select-Object -First 1
}

function Test-RSTExplicitAuthorizationClass {
    param([Parameter(Mandatory)][string]$AuthorizationClass)
    return $AuthorizationClass -eq 'credential-change'
}

function New-RSTPreflightResult {
    param([Parameter(Mandatory)]$Capability, [Parameter(Mandatory)][string]$Operation, [AllowNull()][string]$Target, [Parameter(Mandatory)]$Missing, [Parameter(Mandatory)]$Conflicts, [Parameter(Mandatory)]$Decisions, [Parameter(Mandatory)]$Effects, [switch]$Approved)
    $authorizationRequired = Test-RSTExplicitAuthorizationClass -AuthorizationClass ([string]$Capability.authorization_class)
    $contextComplete = $Missing.Count -eq 0 -and $Conflicts.Count -eq 0
    $authorized = (-not $authorizationRequired) -or $Approved
    return [ordered]@{
        schema_version = 1
        operation = $Operation
        target = if ($Target) { $Target } else { $null }
        state = [string]$Capability.state
        executor = [string]$Capability.executor
        mutation = [bool]$Capability.mutation
        authorization_class = [string]$Capability.authorization_class
        context_complete = $contextComplete
        authorized = $authorized
        ready = ($contextComplete -and $authorized)
        missing_context = @($Missing | Sort-Object -Unique)
        conflicts = @($Conflicts | Sort-Object -Unique)
        user_decisions = @($Decisions | Sort-Object -Unique)
        expected_effects = @($Effects | Sort-Object -Unique)
        rule = 'The agent owns the project workflow, not the user authority.'
    }
}

function New-RSTPreflight {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [AllowNull()][string]$Target,
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        $Context,
        [switch]$Approved
    )
    $capability = Get-RSTCapabilityById -Id $Operation
    $missing = [Collections.Generic.List[string]]::new()
    $conflicts = [Collections.Generic.List[string]]::new()
    $decisions = [Collections.Generic.List[string]]::new()
    $effects = [Collections.Generic.List[string]]::new()

    if ([int](Get-RSTOptional $Inventory 'schema' 0) -ne 1) {
        $conflicts.Add('state-schema-unsupported')
        return New-RSTPreflightResult -Capability $capability -Operation $Operation -Target $Target -Missing $missing -Conflicts $conflicts -Decisions $decisions -Effects $effects -Approved:$Approved
    }
    try { $null = Assert-RSTInventory -Inventory $Inventory -PrivateDirectory $PrivateDirectory }
    catch { $conflicts.Add('inventory-invalid') }

    switch ($Operation) {
        'status' { $effects.Add('read-sanitized-local-state') }
        'drift' { $effects.Add('read-sanitized-local-and-observed-state') }
        'audit' {
            if (-not $Target) { $missing.Add('target-route') }
            elseif (-not (Get-RSTTargetRoute -Inventory $Inventory -Target $Target)) { $conflicts.Add('target-route-missing') }
            $effects.Add('read-remote-supported-state')
        }
        'bootstrap' { $effects.Add('create-local-private-state') }
        'add-server' {
            foreach ($field in 'server_id','public_ipv4','ssh_user','ssh_key_path','host_ownership') { if (-not $Context -or -not (Get-RSTOptional $Context $field)) { $missing.Add($field.Replace('_','-')) } }
            if ($Context -and (Get-RSTOptional $Context 'server_id') -and (Get-RSTTargetServer -Inventory $Inventory -Target ([string]$Context.server_id))) { $conflicts.Add('server-id-already-exists') }
            if ($Context -and (Get-RSTOptional $Context 'ssh_user') -and -not (Test-RSTUnixUser ([string]$Context.ssh_user))) { $conflicts.Add('ssh-user-invalid') }
            if ($Context -and (Get-RSTOptional $Context 'host_ownership') -and [string]$Context.host_ownership -ne 'dedicated') { $conflicts.Add('host-ownership-unsupported') }
            $effects.Add('update-local-desired-state')
        }
        'add-link' {
            foreach ($field in 'link_id','entry_server','exit_server') { if (-not $Context -or -not (Get-RSTOptional $Context $field)) { $missing.Add($field.Replace('_','-')) } }
            if ($Context) {
                if ((Get-RSTOptional $Context 'entry_server') -and -not (Get-RSTTargetServer -Inventory $Inventory -Target ([string]$Context.entry_server))) { $conflicts.Add('entry-server-missing') }
                if ((Get-RSTOptional $Context 'exit_server') -and -not (Get-RSTTargetServer -Inventory $Inventory -Target ([string]$Context.exit_server))) { $conflicts.Add('exit-server-missing') }
                if ((Get-RSTOptional $Context 'entry_server') -and (Get-RSTOptional $Context 'entry_server') -eq (Get-RSTOptional $Context 'exit_server')) { $conflicts.Add('link-endpoints-must-differ') }
            }
            $effects.Add('allocate-local-link-and-keys')
        }
        'add-route' {
            foreach ($field in 'route_id','kind','entry_server') { if (-not $Context -or -not (Get-RSTOptional $Context $field)) { $missing.Add($field.Replace('_','-')) } }
            if ($Context) {
                $kind = [string](Get-RSTOptional $Context 'kind')
                if ($kind -notin @('direct','relay')) { $conflicts.Add('unsupported-route-kind') }
                if ((Get-RSTOptional $Context 'entry_server') -and -not (Get-RSTTargetServer -Inventory $Inventory -Target ([string]$Context.entry_server))) { $conflicts.Add('entry-server-missing') }
                if ($kind -eq 'relay') {
                    if (-not (Get-RSTOptional $Context 'exit_server')) { $missing.Add('exit-server') }
                    if (-not (Get-RSTOptional $Context 'link_id')) { $missing.Add('link-id') }
                }
            }
            $effects.Add('generate-local-route-credentials-and-update-desired-state')
        }
        'add-provider' {
            if (-not $Context -or -not (Get-RSTOptional $Context 'provider_id')) { $missing.Add('provider-id') }
            if (-not $Context -or -not (Get-RSTOptional $Context 'url')) { $missing.Add('provider-url') }
            if ($Context -and (Get-RSTOptional $Context 'provider_id')) {
                $id = ConvertTo-RSTId ([string]$Context.provider_id)
                if (Get-RSTProviderById -Inventory $Inventory -Id $id -AllowMissing) { $conflicts.Add('provider-id-already-exists') }
            }
            $effects.Add('write-provider-url-to-local-secret-storage'); $effects.Add('update-local-desired-state')
        }
        'update-provider' {
            if (-not $Target) { $missing.Add('target-provider') }
            elseif (-not (Get-RSTProviderById -Inventory $Inventory -Id $Target -AllowMissing)) { $conflicts.Add('target-provider-missing') }
            $changes = @(@('url','display_name','interval_seconds','enabled') | Where-Object { $Context -and $Context.PSObject.Properties[$_] })
            if ($changes.Count -eq 0) { $missing.Add('provider-change') }
            $effects.Add('update-local-provider-state')
        }
        'remove-provider' {
            if (-not $Target) { $missing.Add('target-provider') }
            else {
                $provider = Get-RSTProviderById -Inventory $Inventory -Id $Target -AllowMissing
                if (-not $provider) { $conflicts.Add('target-provider-missing') }
                if (@($Inventory.profiles | Where-Object { @(Get-RSTOptional $_ 'include_providers' @()) -contains $Target }).Count) { $conflicts.Add('provider-still-referenced-by-profile') }
            }
            $effects.Add('remove-local-provider-state-and-url-secret')
        }
        'add-profile' {
            if (-not $Context -or -not (Get-RSTOptional $Context 'profile_id')) { $missing.Add('profile-id') }
            elseif (Get-RSTProfileById -Inventory $Inventory -Id (ConvertTo-RSTId ([string]$Context.profile_id)) -AllowMissing) { $conflicts.Add('profile-id-already-exists') }
            $effects.Add('update-local-profile-selection')
        }
        'update-profile' {
            if (-not $Target) { $missing.Add('target-profile') }
            elseif (-not (Get-RSTProfileById -Inventory $Inventory -Id $Target -AllowMissing)) { $conflicts.Add('target-profile-missing') }
            $changes = @(@('policy','include_routes','include_providers') | Where-Object { $Context -and $Context.PSObject.Properties[$_] })
            if ($changes.Count -eq 0) { $missing.Add('profile-change') }
            $effects.Add('update-local-profile-selection')
        }
        'remove-profile' {
            if (-not $Target) { $missing.Add('target-profile') }
            elseif (-not (Get-RSTProfileById -Inventory $Inventory -Id $Target -AllowMissing)) { $conflicts.Add('target-profile-missing') }
            elseif (@(Get-RSTClientTargets -Inventory $Inventory | Where-Object { $_.profile -eq $Target }).Count) { $conflicts.Add('profile-still-referenced-by-client-target') }
            $effects.Add('remove-local-profile')
        }
        'add-client-target' {
            foreach ($field in 'target_id','profile_id','renderer') { if (-not $Context -or -not (Get-RSTOptional $Context $field)) { $missing.Add($field.Replace('_','-')) } }
            if ($Context -and (Get-RSTOptional $Context 'target_id')) {
                $id = ConvertTo-RSTId ([string]$Context.target_id)
                if (Get-RSTClientTargetById -Inventory $Inventory -Id $id -AllowMissing) { $conflicts.Add('client-target-id-already-exists') }
            }
            if ($Context -and (Get-RSTOptional $Context 'profile_id') -and -not (Get-RSTProfileById -Inventory $Inventory -Id ([string]$Context.profile_id) -AllowMissing)) { $conflicts.Add('client-target-profile-missing') }
            if ($Context -and (Get-RSTOptional $Context 'renderer') -and [string]$Context.renderer -notin @('mihomo','shadowrocket')) { $conflicts.Add('client-target-renderer-unsupported') }
            $effects.Add('add-local-client-target')
        }
        'update-client-target' {
            if (-not $Target) { $missing.Add('target-client-target') }
            elseif (-not (Get-RSTClientTargetById -Inventory $Inventory -Id $Target -AllowMissing)) { $conflicts.Add('target-client-target-missing') }
            $changes = @(@('profile_id','delivery') | Where-Object { $Context -and $Context.PSObject.Properties[$_] })
            if ($changes.Count -eq 0) { $missing.Add('client-target-change') }
            if ($Context -and (Get-RSTOptional $Context 'profile_id') -and -not (Get-RSTProfileById -Inventory $Inventory -Id ([string]$Context.profile_id) -AllowMissing)) { $conflicts.Add('client-target-profile-missing') }
            $effects.Add('update-local-client-target')
        }
        'remove-client-target' {
            if (-not $Target) { $missing.Add('target-client-target') }
            else {
                $clientTarget = Get-RSTClientTargetById -Inventory $Inventory -Id $Target -AllowMissing
                if (-not $clientTarget) { $conflicts.Add('target-client-target-missing') }
                elseif (Get-RSTOptional $clientTarget 'subscription_secret_ref') { $conflicts.Add('client-target-has-subscription-state') }
            }
            $effects.Add('remove-local-client-target')
        }
        'deploy-route' {
            $route = Get-RSTTargetRoute -Inventory $Inventory -Target $Target
            if (-not $route) { $missing.Add('target-route') }
            else {
                foreach ($ref in @($route.payload_secret_ref, (Get-RSTOptional $route 'credential_secret_ref')) | Where-Object { $_ }) { try { $null = Resolve-RSTSecret -Reference $ref -PrivateDirectory $PrivateDirectory } catch { $conflicts.Add('required-secret-missing') } }
                foreach ($serverId in @($route.entry_server, $route.exit_server) | Sort-Object -Unique) {
                    $server = Get-RSTTargetServer -Inventory $Inventory -Target ([string]$serverId)
                    if (-not $server) { $conflicts.Add('server-missing'); continue }
                    if ([string](Get-RSTOptional (Get-RSTOptional $server 'compute') 'host_ownership') -ne 'dedicated') { $conflicts.Add('dedicated-host-not-confirmed') }
                    if (-not (Test-RSTUnixUser ([string](Get-RSTOptional (Get-RSTOptional $server 'ssh') 'user')))) { $conflicts.Add('ssh-user-invalid') }
                    if (-not (Test-Path -LiteralPath ([string]$server.ssh.key_path) -PathType Leaf)) { $conflicts.Add('ssh-key-missing') }
                }
                $effects.Add("deploy-route:$($route.id)")
            }
        }
        'render-client' {
            if ($Target -and -not (Get-RSTClientTargetById -Inventory $Inventory -Id $Target -AllowMissing)) { $conflicts.Add('target-client-target-missing') }
            if (@($Inventory.routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false }).Count -eq 0) { $missing.Add('enabled-route') }
            $effects.Add('write-private-client-artifacts')
        }
        'publish-subscription' {
            if (-not $Target) { $missing.Add('target-client-target') }
            else {
                $clientTarget = Get-RSTClientTargetById -Inventory $Inventory -Id $Target -AllowMissing
                if (-not $clientTarget -or [string]$clientTarget.renderer -ne 'shadowrocket') { $conflicts.Add('target-client-target-not-shadowrocket') }
                else {
                    $reference = [string](Get-RSTOptional $clientTarget 'subscription_secret_ref')
                    if (-not $reference) {
                        if (-not $Context -or -not (Get-RSTOptional $Context 'worker_name')) { $missing.Add('worker-name') }
                        if (-not $Context -or -not (Get-RSTOptional $Context 'host')) { $missing.Add('host') }
                    }
                    else { try { $null = Resolve-RSTSecret -Reference $reference -PrivateDirectory $PrivateDirectory } catch { $conflicts.Add('subscription-state-missing') } }
                }
            }
            if (@($Inventory.routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false }).Count -eq 0) { $missing.Add('enabled-route') }
            $effects.Add('publish-private-subscription-payload')
        }
        'rotate-subscription-token' {
            if (-not $Target) { $missing.Add('target-client-target') }
            else {
                $clientTarget = Get-RSTClientTargetById -Inventory $Inventory -Id $Target -AllowMissing
                if (-not $clientTarget) { $conflicts.Add('target-client-target-missing') }
                elseif ([string]$clientTarget.renderer -ne 'shadowrocket') { $conflicts.Add('target-client-target-not-shadowrocket') }
                elseif (-not (Get-RSTOptional $clientTarget 'subscription_secret_ref')) { $conflicts.Add('client-target-has-no-subscription-state') }
            }
            $decisions.Add('explicit-current-authorization-for-target-scoped-token-rotation')
            $effects.Add('rotate-only-one-client-target-subscription-token'); $effects.Add('require-subscription-republication'); $effects.Add('leave-route-and-other-client-credentials-unchanged')
        }
        'migrate-route' {
            $route = Get-RSTTargetRoute -Inventory $Inventory -Target $Target
            if (-not $route) { $missing.Add('target-route') }
            if (-not $Context -or -not (Get-RSTOptional $Context 'replacement_server_id')) { $missing.Add('replacement-server') }
            elseif (-not (Get-RSTTargetServer -Inventory $Inventory -Target ([string]$Context.replacement_server_id))) { $conflicts.Add('replacement-server-not-in-inventory') }
            $effects.Add('create-and-validate-overlap-before-any-retirement')
        }
        'backup' { $effects.Add('write-encrypted-local-recovery-archive') }
        'recover' { $effects.Add('restore-local-canonical-state') }
    }

    return New-RSTPreflightResult -Capability $capability -Operation $Operation -Target $Target -Missing $missing -Conflicts $conflicts -Decisions $decisions -Effects $effects -Approved:$Approved
}

function Add-RSTServer {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $id = ConvertTo-RSTId ([string]$Context.server_id)
    if (Get-RSTTargetServer -Inventory $Inventory -Target $id) { throw "Server '$id' already exists." }
    $publicV4 = [string]$Context.public_ipv4
    if (-not (Test-RSTIPv4 $publicV4)) { throw 'public_ipv4 is invalid.' }
    $publicV6 = [string](Get-RSTOptional $Context 'public_ipv6')
    if ($publicV6 -and -not (Test-RSTIPv6 $publicV6)) { throw 'public_ipv6 is invalid.' }
    $privateV4 = [string](Get-RSTOptional $Context 'private_ipv4')
    if ($privateV4 -and -not (Test-RSTIPv4 $privateV4)) { throw 'private_ipv4 is invalid.' }
    $sshUser = [string](Get-RSTOptional $Context 'ssh_user')
    if (-not (Test-RSTUnixUser $sshUser)) { throw 'ssh_user must be a lowercase Unix account name with at most 32 characters.' }
    $hostOwnership = [string](Get-RSTOptional $Context 'host_ownership')
    if ($hostOwnership -ne 'dedicated') { throw 'host_ownership must be dedicated.' }
    $keyPath = [IO.Path]::GetFullPath([string]$Context.ssh_key_path)
    $server = [pscustomobject][ordered]@{
        id = $id
        provider = [string](Get-RSTOptional $Context 'provider' 'byo')
        account_label = [string](Get-RSTOptional $Context 'account_label' 'personal')
        instance_name = [string](Get-RSTOptional $Context 'instance_name' $id)
        region = [string](Get-RSTOptional $Context 'region' 'unknown')
        zone = [string](Get-RSTOptional $Context 'zone' '')
        os = [string](Get-RSTOptional $Context 'os' 'ubuntu-24.04')
        architecture = [string](Get-RSTOptional $Context 'architecture' 'x86_64')
        roles = @(Get-RSTOptional $Context 'roles' @('entry','exit'))
        compute = [pscustomobject][ordered]@{ driver = 'byo-ssh'; host_ownership = $hostOwnership }
        network = [pscustomobject][ordered]@{ public_ipv4 = $publicV4; ipv4_type = 'static'; private_ipv4 = $privateV4; public_ipv6 = $publicV6; expected_egress_ipv4 = [string](Get-RSTOptional $Context 'expected_egress_ipv4' $publicV4); expected_egress_ipv6 = Get-RSTOptional $Context 'expected_egress_ipv6' }
        ssh = [pscustomobject][ordered]@{ user = $sshUser; key_path = $keyPath; allowed_sources = @(Get-RSTOptional $Context 'ssh_allowed_sources' @('trusted')) }
        firewall = [pscustomobject][ordered]@{ profile = 'pending'; rules = @([pscustomobject][ordered]@{ family = 'dual'; protocol = 'tcp'; port = 22; source = 'trusted' }) }
    }
    $Inventory.servers = @($Inventory.servers) + $server
    Save-RSTInventory -Inventory $Inventory -InventoryPath $InventoryPath -SkipSecretCheck
    return $server
}

function Add-RSTLink {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $id = ConvertTo-RSTId ([string]$Context.link_id)
    $entry = [string]$Context.entry_server; $exit = [string]$Context.exit_server
    $null = Get-RSTServerById -Inventory $Inventory -Id $entry; $null = Get-RSTServerById -Inventory $Inventory -Id $exit
    if ($entry -eq $exit) { throw 'A Link requires different entry and exit Servers.' }
    if (@($Inventory.links | Where-Object id -eq $id).Count) { throw "Link '$id' already exists." }
    $allocation = New-RSTLinkAllocation -Inventory $Inventory
    $third = ($allocation.subnet -split '\.')[2]
    $secretReference = "link-key:$id"; $secretRelative = "managed-links/$id/keys.json"
    $managedDirectory = Join-Path $privateDirectory ("secrets\managed-links\$id"); $secretPath = Join-Path $managedDirectory 'keys.json'
    $link = [pscustomobject][ordered]@{ id = $id; type = 'wireguard'; driver = 'wireguard'; entry_server = $entry; exit_server = $exit; slot = $allocation.slot; interface = $allocation.interface; listen_port = $allocation.listen_port; subnet = $allocation.subnet; entry_address = "10.77.$third.1/30"; exit_address = "10.77.$third.2/30"; endpoint_family = 'ipv4'; secret_ref = $secretReference; enabled = $true }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.links = @($candidate.links) + $link
    $candidateExit = @($candidate.servers | Where-Object id -eq $exit)[0]
    $candidateExit.firewall.rules = @($candidateExit.firewall.rules) + [pscustomobject][ordered]@{ family = 'ipv4'; protocol = 'udp'; port = $allocation.listen_port; source_server = $entry }
    $null = Assert-RSTInventory -Inventory $candidate -PrivateDirectory $privateDirectory -SkipSecretCheck
    $secretIndex = Read-RSTSecretIndex -PrivateDirectory $privateDirectory
    if ($secretIndex.refs.PSObject.Properties[$secretReference]) { throw "Secret reference '$secretReference' already exists." }
    $indexPath = Join-Path $privateDirectory 'secrets\index.json'; $indexWritten = $false
    try {
        & (Join-Path $repoRoot 'scripts\New-ManagedLinkSecret.ps1') -LinkId $id -OutputPath $secretPath
        $secretIndex.refs | Add-Member -NotePropertyName $secretReference -NotePropertyValue ([pscustomobject][ordered]@{ type = 'managed-link-key'; path = $secretRelative })
        Write-RSTJsonAtomic -Value $secretIndex -Path $indexPath; $indexWritten = $true
        Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    } catch {
        if ($indexWritten) { $secretIndex.refs.PSObject.Properties.Remove($secretReference); Write-RSTJsonAtomic -Value $secretIndex -Path $indexPath }
        if (Test-Path -LiteralPath $managedDirectory) { Remove-Item -LiteralPath $managedDirectory -Recurse -Force }
        throw
    }
    return $link
}

function Add-RSTRoute {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$InventoryPath, [Parameter(Mandatory)]$Context)
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $id = ConvertTo-RSTId ([string]$Context.route_id)
    if (@($Inventory.routes | Where-Object id -eq $id).Count) { throw "Route '$id' already exists." }
    $kind = ([string]$Context.kind).ToLowerInvariant(); if ($kind -notin @('direct','relay')) { throw 'Route kind must be direct or relay.' }
    $entry = [string]$Context.entry_server; $entryServer = Get-RSTServerById -Inventory $Inventory -Id $entry
    $exit = if ($kind -eq 'direct') { $entry } else { [string]$Context.exit_server }; $null = Get-RSTServerById -Inventory $Inventory -Id $exit
    $link = if ($kind -eq 'relay') { [string]$Context.link_id } else { $null }
    if ($kind -eq 'relay') { $linkObject = Get-RSTLinkById -Inventory $Inventory -Id $link; if ($linkObject.entry_server -ne $entry -or $linkObject.exit_server -ne $exit) { throw 'The Link does not match Route endpoints.' } }
    $defaultPort = if ($kind -eq 'direct') { 443 } else { $used = @($Inventory.routes | Where-Object entry_server -eq $entry | ForEach-Object { [int]$_.listen_port }); $p = 8443; while ($used -contains $p) { $p++ }; $p }
    $port = [int](Get-RSTOptional $Context 'listen_port' $defaultPort); if ($port -lt 1 -or $port -gt 65535) { throw 'listen_port is invalid.' }
    $displayName = [string](Get-RSTOptional $Context 'display_name' $id); if ($displayName -notmatch '^[A-Za-z0-9._-]+$') { throw 'display_name must use ASCII letters, digits, dot, underscore, or dash.' }
    $managedRelative = "managed-routes/$id"; $managedDirectory = Join-Path $privateDirectory ("secrets\managed-routes\$id")
    $payloadRef = "route-payload:$id"; $credentialRef = "route-credential:$id"
    $route = [pscustomobject][ordered]@{ id = $id; display_name = $displayName; kind = $kind; ingress = [pscustomobject][ordered]@{ driver = 'hysteria2' }; entry_server = $entry; exit_server = $exit; link = $link; listen_port = $port; enabled = $false; order = @($Inventory.routes).Count + 1; address_families = @('ipv6','ipv4'); payload_secret_ref = $payloadRef; credential_secret_ref = $credentialRef; credential_mode = 'personal-pinned'; state = 'pending' }
    $candidate = $Inventory | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $candidate.routes = @($candidate.routes) + $route
    $candidateEntry = @($candidate.servers | Where-Object id -eq $entry)[0]
    $candidateEntry.firewall.rules = @($candidateEntry.firewall.rules) + [pscustomobject][ordered]@{ family = 'dual'; protocol = 'udp'; port = $port; source = 'any' }
    $null = Assert-RSTInventory -Inventory $candidate -PrivateDirectory $privateDirectory -SkipSecretCheck
    $secretIndex = Read-RSTSecretIndex -PrivateDirectory $privateDirectory; $indexPath = Join-Path $privateDirectory 'secrets\index.json'; $indexWritten = $false
    foreach ($ref in $payloadRef,$credentialRef) { if ($secretIndex.refs.PSObject.Properties[$ref]) { throw "Secret reference '$ref' already exists." } }
    try {
        & (Join-Path $repoRoot 'scripts\New-ManagedRouteSecret.ps1') -RouteId $id -DisplayName $displayName -EntryIPv4 ([string]$entryServer.network.public_ipv4) -EntryIPv6 ([string](Get-RSTOptional $entryServer.network 'public_ipv6')) -Port $port -SecretDirectory $managedDirectory
        $secretIndex.refs | Add-Member -NotePropertyName $payloadRef -NotePropertyValue ([pscustomobject][ordered]@{ type = 'client-payload'; path = "$managedRelative/client-payload.yaml" })
        $secretIndex.refs | Add-Member -NotePropertyName $credentialRef -NotePropertyValue ([pscustomobject][ordered]@{ type = 'managed-route-credential'; path = "$managedRelative/credentials.json" })
        Write-RSTJsonAtomic -Value $secretIndex -Path $indexPath; $indexWritten = $true
        Save-RSTInventory -Inventory $candidate -InventoryPath $InventoryPath
    } catch {
        if ($indexWritten) { $secretIndex.refs.PSObject.Properties.Remove($payloadRef); $secretIndex.refs.PSObject.Properties.Remove($credentialRef); Write-RSTJsonAtomic -Value $secretIndex -Path $indexPath }
        if (Test-Path -LiteralPath $managedDirectory) { Remove-Item -LiteralPath $managedDirectory -Recurse -Force }
        throw
    }
    return $route
}
