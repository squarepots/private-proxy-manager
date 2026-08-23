[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('capabilities','bootstrap','context','drift','preflight','execute')][string]$Command = 'context',
    [string]$Operation,
    [string]$Target,
    [string]$ContextJson,
    [switch]$ContextStdin,
    [string]$PrivateDirectory,
    [switch]$Approved
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\PrivateProxyManager.Core.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Model.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Provider.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Agent.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Subscription.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.SubscriptionTargets.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.ClientState.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Observed.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Execution.ps1')

if (-not $PrivateDirectory) { $PrivateDirectory = Join-Path $repo 'private' }
$PrivateDirectory = [IO.Path]::GetFullPath($PrivateDirectory)
$inventoryPath = Join-Path $PrivateDirectory 'inventory.json'

function Write-AgentJson {
    param([Parameter(Mandatory)]$Value)
    $Value | ConvertTo-Json -Depth 24 -Compress
}

function Read-AgentContext {
    if ($ContextStdin -and $ContextJson) { throw 'Use either ContextJson or ContextStdin, not both.' }
    $raw = $ContextJson
    if ($ContextStdin) { $raw = [Console]::In.ReadToEnd() }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return $raw | ConvertFrom-Json }
    catch { throw 'Agent context is not valid JSON.' }
}

function Read-AgentState {
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw 'Private state is not initialized. Run bootstrap first.' }
    $inventory = Read-PPMStateInventory -Path $inventoryPath
    return [pscustomobject]@{ Inventory = $inventory }
}

function New-AgentResult {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][bool]$Success, $Data = $null, [string]$Code = 'ok')
    return [ordered]@{ schema_version = 1; command = $Name; success = $Success; code = $Code; data = $Data }
}

function New-SanitizedAuditResult {
    param([Parameter(Mandatory)]$Evidence)
    return [ordered]@{
        route = [string]$Evidence.route
        status = [string]$Evidence.status
        category = [string](Get-PPMOptional $Evidence 'category' 'in-sync')
        egress_matches_declared_exit = [bool](Get-PPMOptional $Evidence 'egress_matches_declared_exit' $true)
        versions_observed = [ordered]@{
            hysteria = [bool](Get-PPMOptional $Evidence 'hysteria_version')
            wireguard = [bool](Get-PPMOptional $Evidence 'wireguard_version')
        }
    }
}

function ConvertTo-AgentRenderResult {
    param([Parameter(Mandatory)]$Render)
    $sanitizedOutputs = @($Render.outputs | ForEach-Object {
        $output = $_
        $fileName = [IO.Path]::GetFileName([string]$output.path)
        if ([string]::IsNullOrWhiteSpace($fileName)) { throw 'A rendered artifact is missing its file name.' }
        $item = [ordered]@{}
        foreach ($property in $output.PSObject.Properties) {
            if ($property.Name -ne 'path') { $item[$property.Name] = $property.Value }
        }
        $item['artifact'] = [ordered]@{
            id = [string]$output.client_target
            file_name = $fileName
            relative_path = '<private>/delivery/' + $fileName
        }
        [pscustomobject]$item
    })
    return [ordered]@{
        schema_version = [int]$Render.schema_version
        command = [string]$Render.command
        success = [bool]$Render.success
        outputs = $sanitizedOutputs
    }
}

function New-RecoveryPreflight {
    param($Context)
    $missing = [Collections.Generic.List[string]]::new()
    $conflicts = [Collections.Generic.List[string]]::new()
    $archivePath = [string](Get-PPMOptional $Context 'archive_path')
    if (-not $archivePath) { $missing.Add('recovery-archive-path') }
    else {
        try { $archivePath = [IO.Path]::GetFullPath($archivePath) }
        catch { $conflicts.Add('recovery-archive-path-invalid') }
        if ($archivePath -and -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { $conflicts.Add('recovery-archive-missing') }
    }
    if (Test-Path -LiteralPath $PrivateDirectory) { $conflicts.Add('private-state-target-already-exists') }
    $ready = $missing.Count -eq 0 -and $conflicts.Count -eq 0
    return [ordered]@{
        schema_version = 1; operation = 'recover'; target = $null; state = 'supported'; executor = 'local-assisted'
        mutation = $true; authorization_class = 'local-write'; context_complete = $ready; authorized = $true; ready = $ready
        missing_context = @($missing); conflicts = @($conflicts); user_decisions = @('enter-recovery-password-only-in-local-7zip-prompt')
        expected_effects = @('restore-local-canonical-private-state','rewrite-restored-ssh-key-paths','reset-observed-state','no-remote-infrastructure-change')
        requires_local_secret_prompt = $true; rule = 'The agent owns the project workflow, not the user authority.'
    }
}

function New-LocalAssistanceResult {
    param([Parameter(Mandatory)][string]$Operation, [Parameter(Mandatory)][string]$Script)
    return [ordered]@{
        operation = $Operation; executor = 'local-assisted'; repository_script = $Script; requires_local_secret_prompt = $true
        secret_prompt_rule = 'The password must stay in the local 7-Zip prompt and must not enter the model, MCP stream, process arguments, repository files, or logs.'
        remote_changed = $false
    }
}

try {
    switch ($Command) {
        'capabilities' {
            Write-AgentJson (New-AgentResult -Name capabilities -Success $true -Data ([ordered]@{
                product = 'private-proxy-manager'; interface = 'agent-machine-surface'; rule = 'The agent owns the project workflow, not the user authority.'
                capabilities = @(Get-PPMCapabilityCatalog); drivers = Get-PPMDriverCapabilities
            }))
        }
        'bootstrap' {
            $state = Initialize-PPMPrivateState -PrivateDirectory $PrivateDirectory
            $inventory = Read-PPMStateInventory -Path $state.inventory_path
            Write-AgentJson (New-AgentResult -Name bootstrap -Success $true -Data ([ordered]@{ created = [bool]$state.created; context = Get-PPMSanitizedContext -Inventory $inventory }))
        }
        'context' {
            $state = Read-AgentState
            Write-AgentJson (New-AgentResult -Name context -Success $true -Data (Get-PPMSanitizedContext -Inventory $state.Inventory))
        }
        'drift' {
            $state = Read-AgentState
            Write-AgentJson (New-AgentResult -Name drift -Success $true -Data (Get-PPMDriftReport -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -InventoryPath $inventoryPath))
        }
        'preflight' {
            if (-not $Operation) { throw 'Operation is required for preflight.' }
            $requestContext = Read-AgentContext
            if ($Operation -eq 'recover') { Write-AgentJson (New-AgentResult -Name preflight -Success $true -Data (New-RecoveryPreflight -Context $requestContext)); break }
            $state = Read-AgentState
            $preflight = New-PPMPreflight -Operation $Operation -Target $Target -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -Context $requestContext -Approved:$Approved
            Write-AgentJson (New-AgentResult -Name preflight -Success $true -Data $preflight)
        }
        'execute' {
            if (-not $Operation) { throw 'Operation is required for execute.' }
            if ($Operation -eq 'bootstrap') {
                $state = Initialize-PPMPrivateState -PrivateDirectory $PrivateDirectory
                $inventory = Read-PPMStateInventory -Path $state.inventory_path
                Write-AgentJson (New-AgentResult -Name execute -Success $true -Data ([ordered]@{ operation = 'bootstrap'; created = [bool]$state.created; context = Get-PPMSanitizedContext -Inventory $inventory }))
                break
            }
            $requestContext = Read-AgentContext
            if ($Operation -eq 'recover') {
                $preflight = New-RecoveryPreflight -Context $requestContext
                if (-not $preflight.ready) { Write-AgentJson (New-AgentResult -Name execute -Success $false -Code 'context-gate-blocked' -Data $preflight); exit 2 }
                Write-AgentJson (New-AgentResult -Name execute -Success $false -Code 'local-assistance-required' -Data ([ordered]@{ preflight = $preflight; result = New-LocalAssistanceResult -Operation recover -Script 'scripts/Restore-RecoveryArchive.ps1' })); exit 3
            }

            $state = Read-AgentState
            $preflight = New-PPMPreflight -Operation $Operation -Target $Target -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -Context $requestContext -Approved:$Approved
            if (-not $preflight.ready) { Write-AgentJson (New-AgentResult -Name execute -Success $false -Code 'context-gate-blocked' -Data $preflight); exit 2 }

            $resultData = $null
            switch ($Operation) {
                'status' { $resultData = Get-PPMSanitizedContext -Inventory $state.Inventory }
                'add-server' {
                    $created = Add-PPMServer -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; compute_driver = 'byo-ssh'; host_ownership = [string]$created.compute.host_ownership; state = 'desired-only'; remote_changed = $false }
                }
                'add-link' {
                    $created = Add-PPMLink -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; driver = 'wireguard'; state = 'desired-only'; remote_changed = $false }
                }
                'add-route' {
                    $created = Add-PPMRoute -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; ingress_driver = 'hysteria2'; state = 'pending'; enabled = $false; remote_changed = $false }
                }
                'add-provider' {
                    $created = Add-PPMProvider -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; source_type = 'mihomo-http'; enabled = [bool]$created.enabled; url_stored_as_secret = $true; remote_changed = $false }
                }
                'update-provider' {
                    if (-not $Target) { throw 'Target is required for update-provider.' }
                    $updated = Update-PPMProvider -Inventory $state.Inventory -InventoryPath $inventoryPath -ProviderId $Target -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$updated.id; enabled = [bool]$updated.enabled; url_stored_as_secret = $true; remote_changed = $false }
                }
                'remove-provider' {
                    if (-not $Target) { throw 'Target is required for remove-provider.' }
                    $resultData = Remove-PPMProvider -Inventory $state.Inventory -InventoryPath $inventoryPath -ProviderId $Target
                }
                'add-profile' {
                    $created = Add-PPMProfile -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; role = 'route-provider-policy-selection'; remote_changed = $false }
                }
                'update-profile' {
                    if (-not $Target) { throw 'Target is required for update-profile.' }
                    $updated = Update-PPMProfile -Inventory $state.Inventory -InventoryPath $inventoryPath -ProfileId $Target -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$updated.id; remote_changed = $false }
                }
                'remove-profile' {
                    if (-not $Target) { throw 'Target is required for remove-profile.' }
                    $resultData = Remove-PPMProfile -Inventory $state.Inventory -InventoryPath $inventoryPath -ProfileId $Target
                }
                'add-client-target' {
                    $created = Add-PPMClientTarget -Inventory $state.Inventory -InventoryPath $inventoryPath -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$created.id; profile = [string]$created.profile; renderer = [string]$created.renderer; delivery = [string]$created.delivery; remote_changed = $false }
                }
                'update-client-target' {
                    if (-not $Target) { throw 'Target is required for update-client-target.' }
                    $updated = Update-PPMClientTarget -Inventory $state.Inventory -InventoryPath $inventoryPath -TargetId $Target -Context $requestContext
                    $resultData = [ordered]@{ id = [string]$updated.id; profile = [string]$updated.profile; renderer = [string]$updated.renderer; delivery = [string]$updated.delivery; remote_changed = $false }
                }
                'remove-client-target' {
                    if (-not $Target) { throw 'Target is required for remove-client-target.' }
                    $resultData = Remove-PPMClientTarget -Inventory $state.Inventory -InventoryPath $inventoryPath -TargetId $Target
                }
                'audit' {
                    if (-not $Target) { throw 'Target is required for the agent audit surface.' }
                    $evidence = Audit-PPMRoute -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -RouteId $Target
                    $null = Set-PPMObservedRoute -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -RouteId $Target -Status ([string]$evidence.status) -Category ([string](Get-PPMOptional $evidence 'category' 'undetermined')) -ActualEgressIPv4 ([string](Get-PPMOptional $evidence 'actual_egress_ipv4')) -HysteriaVersion ([string](Get-PPMOptional $evidence 'hysteria_version')) -WireGuardVersion ([string](Get-PPMOptional $evidence 'wireguard_version'))
                    $resultData = New-SanitizedAuditResult -Evidence $evidence
                }
                'deploy-route' {
                    if (-not $Target) { throw 'Target is required for deploy-route.' }
                    $deploy = Deploy-PPMRoute -Inventory $state.Inventory -InventoryPath $inventoryPath -RouteId $Target -SkipClientValidation
                    $freshInventory = Read-PPMInventory -Path $inventoryPath
                    if ($deploy.render -and $deploy.render.outputs) { $null = Update-PPMClientRenderManifest -Inventory $freshInventory -InventoryPath $inventoryPath -PrivateDirectory $PrivateDirectory -Outputs @($deploy.render.outputs) }
                    $evidence = Audit-PPMRoute -Inventory $freshInventory -PrivateDirectory $PrivateDirectory -RouteId $Target
                    $null = Set-PPMObservedRoute -Inventory $freshInventory -PrivateDirectory $PrivateDirectory -RouteId $Target -Status ([string]$evidence.status) -Category ([string](Get-PPMOptional $evidence 'category' 'undetermined')) -ActualEgressIPv4 ([string](Get-PPMOptional $evidence 'actual_egress_ipv4')) -HysteriaVersion ([string](Get-PPMOptional $evidence 'hysteria_version')) -WireGuardVersion ([string](Get-PPMOptional $evidence 'wireguard_version'))
                    if ([string]$evidence.status -ne 'healthy') { throw 'Route deployment completed but post-deploy audit is not healthy.' }
                    $sanitizedRender = if ($deploy.render) { ConvertTo-AgentRenderResult -Render $deploy.render } else { $null }
                    $resultData = [ordered]@{ route = [string]$deploy.route; state = 'deployed'; enabled = $true; validation = (New-SanitizedAuditResult -Evidence $evidence); render = $sanitizedRender }
                }
                'render-client' {
                    $args = @{ InventoryPath = $inventoryPath; SkipValidation = $false }
                    if ($Target) { $args.ClientTargetId = $Target }
                    $renderJson = & (Join-Path $repo 'client\Render-ClientTargets.ps1') @args
                    if ($LASTEXITCODE -ne 0) { throw 'render-failed' }
                    $render = $renderJson | ConvertFrom-Json
                    $freshInventory = Read-PPMInventory -Path $inventoryPath
                    $null = Update-PPMClientRenderManifest -Inventory $freshInventory -InventoryPath $inventoryPath -PrivateDirectory $PrivateDirectory -Outputs @($render.outputs)
                    $resultData = ConvertTo-AgentRenderResult -Render $render
                }
                'publish-subscription' {
                    if (-not $Target) { throw 'Target is required for publish-subscription.' }
                    $subscriptionState = Get-PPMClientSubscriptionState -Inventory $state.Inventory -PrivateDirectory $PrivateDirectory -TargetId $Target -AllowMissing
                    if (-not $subscriptionState) {
                        $workerName = [string](Get-PPMOptional $requestContext 'worker_name')
                        $hostName = [string](Get-PPMOptional $requestContext 'host')
                        $subscriptionState = Initialize-PPMClientSubscriptionState -Inventory $state.Inventory -InventoryPath $inventoryPath -TargetId $Target -WorkerName $workerName -HostName $hostName
                    }
                    $freshInventory = Read-PPMInventory -Path $inventoryPath
                    $publish = Publish-PPMClientSubscription -Inventory $freshInventory -InventoryPath $inventoryPath -TargetId $Target
                    $resultData = [ordered]@{ client_target = [string]$publish.client_target; worker = [string]$publish.worker; published = [bool]$publish.published; verified = [bool]$publish.verified }
                }
                'rotate-subscription-token' {
                    if (-not $Target) { throw 'Target is required for rotate-subscription-token.' }
                    $resultData = Rotate-PPMClientSubscriptionToken -Inventory $state.Inventory -InventoryPath $inventoryPath -TargetId $Target
                }
                'backup' {
                    Write-AgentJson (New-AgentResult -Name execute -Success $false -Code 'local-assistance-required' -Data ([ordered]@{ preflight = $preflight; result = New-LocalAssistanceResult -Operation backup -Script 'scripts/New-RecoveryArchive.ps1' })); exit 3
                }
                'migrate-route' {
                    $resultData = [ordered]@{ operation = 'migrate-route'; executor = 'workflow'; next = @('create replacement Server/Link/Route as needed','deploy replacement while old route remains enabled','audit replacement','render ClientTargets','verify replacement','only retire old capacity after explicit destructive authorization if requested'); old_capacity_retired = $false }
                }
                default { throw "Operation '$Operation' is not directly executable by the local PPM machine surface." }
            }
            Write-AgentJson (New-AgentResult -Name execute -Success $true -Data ([ordered]@{ preflight = $preflight; result = $resultData }))
        }
    }
}
catch {
    $errorCode = if ($_.Exception.Message -eq 'subscription-payload-too-large') { 'subscription-payload-too-large' } else { 'operation-failed' }
    Write-AgentJson (New-AgentResult -Name $Command -Success $false -Code $errorCode -Data ([ordered]@{ summary = 'The operation failed locally. No secret-bearing diagnostic was returned through the agent surface.' }))
    exit 1
}
