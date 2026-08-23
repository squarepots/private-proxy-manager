$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-PPMRouteOperation {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)]$RouteObject,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [switch]$AuditOnly
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $entry = Get-PPMServerById -Inventory $Inventory -Id ([string]$RouteObject.entry_server)
    $exit = Get-PPMServerById -Inventory $Inventory -Id ([string]$RouteObject.exit_server)
    foreach ($server in @($entry, $exit)) {
        if ([string](Get-PPMOptional (Get-PPMOptional $server 'compute') 'host_ownership') -ne 'dedicated') { throw 'Route deployment requires dedicated host ownership.' }
        if (-not (Test-PPMUnixUser ([string](Get-PPMOptional (Get-PPMOptional $server 'ssh') 'user')))) { throw 'Route deployment rejected an invalid SSH user.' }
    }
    $credentialReference = [string](Get-PPMOptional $RouteObject 'credential_secret_ref')
    $credentialDirectory = $null
    if ($credentialReference) {
        $credentialFile = Resolve-PPMSecret -Reference $credentialReference -PrivateDirectory $PrivateDirectory
        $credentialDirectory = Split-Path -Parent $credentialFile
    }

    $arguments = @{}
    $scriptPath = $null
    if ([string]$RouteObject.kind -eq 'relay') {
        $link = Get-PPMLinkById -Inventory $Inventory -Id ([string]$RouteObject.link)
        $arguments = @{
            EntryHost = [string]$entry.network.public_ipv4
            EntryUser = [string]$entry.ssh.user
            EntrySshKey = [string]$entry.ssh.key_path
            ExitHost = [string]$exit.network.public_ipv4
            ExitUser = [string]$exit.ssh.user
            ExitSshKey = [string]$exit.ssh.key_path
            Name = [string]$RouteObject.display_name
            ViaName = [string]$entry.id
            ProxyPort = [int]$RouteObject.listen_port
            TunnelPort = [int]$link.listen_port
            Interface = [string]$link.interface
            TunnelSubnet = [string]$link.subnet
            EntryTunnelAddress = [string]$link.entry_address
            ExitTunnelAddress = [string]$link.exit_address
        }
        $entryIPv6 = [string](Get-PPMOptional $entry.network 'public_ipv6')
        if ($entryIPv6) { $arguments.EntryIPv6 = $entryIPv6 }
        $linkSecretReference = [string](Get-PPMOptional $link 'secret_ref')
        if ($linkSecretReference) { $arguments.LinkSecretPath = Resolve-PPMSecret -Reference $linkSecretReference -PrivateDirectory $PrivateDirectory }
        if ($AuditOnly) { $arguments.AuditOnly = $true }
        else { $arguments.OutputPayloadPath = Resolve-PPMSecret -Reference ([string]$RouteObject.payload_secret_ref) -PrivateDirectory $PrivateDirectory }
        if ($credentialDirectory) { $arguments.CredentialBundleDirectory = $credentialDirectory }
        $scriptPath = Join-Path $repoRoot 'Deploy-Relay.ps1'
    }
    else {
        $arguments = @{
            ServerHost = [string]$entry.network.public_ipv4
            User = [string]$entry.ssh.user
            SshKey = [string]$entry.ssh.key_path
            Name = [string]$RouteObject.display_name
            ProxyPort = [int]$RouteObject.listen_port
        }
        $ipv6 = [string](Get-PPMOptional $entry.network 'public_ipv6')
        if ($ipv6) { $arguments.IPv6 = $ipv6 }
        if ($AuditOnly) { $arguments.AuditOnly = $true }
        else { $arguments.OutputPayloadPath = Resolve-PPMSecret -Reference ([string]$RouteObject.payload_secret_ref) -PrivateDirectory $PrivateDirectory }
        if ($credentialDirectory) { $arguments.CredentialBundleDirectory = $credentialDirectory }
        $scriptPath = Join-Path $repoRoot 'Deploy-Server.ps1'
    }

    # The agent surface owns stdout. Capture all lower-level output so private
    # SSH/server diagnostics never become model-visible. Audit wrappers emit a
    # bounded set of PPM_* markers and evidence fields; deployment failures are
    # still terminating operations.
    $operationOutput = @(& $scriptPath @arguments *>&1 | ForEach-Object { [string]$_ })
    if (-not $AuditOnly -and $LASTEXITCODE -ne 0) { throw 'The deterministic route operation failed.' }
    return $operationOutput
}

function Get-PPMAuditEvidenceFromOutput {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)]$Route,
        [Parameter(Mandatory)][string[]]$Output
    )
    $actual = $null
    $hysteriaVersion = $null
    $wireGuardVersion = $null
    $category = $null
    foreach ($line in $Output) {
        if ($line -match '^IPV4=(?<value>.+)$' -or $line -match '^RELAY_EGRESS_IPV4=(?<value>.+)$') { $actual = $Matches.value.Trim() }
        elseif ($line -match '^HYSTERIA_VERSION=(?<value>.+)$') { $hysteriaVersion = $Matches.value.Trim() }
        elseif ($line -match '^WIREGUARD_VERSION=(?<value>.+)$') { $wireGuardVersion = $Matches.value.Trim() }
        elseif ($line -match '^PPM_AUDIT_CATEGORY=(?<value>[a-z0-9-]+)$') { $category = $Matches.value.Trim() }
    }
    if (-not $category) { $category = 'undetermined' }
    $allowed = @('in-sync','service-missing','remote-config-mismatch','firewall-network-mismatch','wireguard-link-mismatch','hysteria-listener-mismatch','certificate-mismatch','egress-mismatch','undetermined')
    if ($category -notin $allowed) { $category = 'undetermined' }

    $exit = Get-PPMServerById -Inventory $Inventory -Id ([string]$Route.exit_server)
    $expected = [string]$exit.network.expected_egress_ipv4
    if ($category -eq 'in-sync') {
        if (-not $actual) { $category = 'undetermined' }
        elseif ($actual -ne $expected) { $category = 'egress-mismatch' }
    }
    $status = if ($category -eq 'in-sync') { 'healthy' } elseif ($category -eq 'undetermined') { 'undetermined' } else { 'mismatch' }
    return [ordered]@{
        route = [string]$Route.id
        status = $status
        category = $category
        actual_egress_ipv4 = $actual
        egress_matches_declared_exit = [bool]($actual -and $actual -eq $expected)
        hysteria_version = $hysteriaVersion
        wireguard_version = $wireGuardVersion
    }
}

function Deploy-PPMRoute {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$RouteId,
        [switch]$SkipClientValidation
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $route = Get-PPMRouteById -Inventory $Inventory -Id $RouteId

    # An already-deployed Route must be observed healthy before it can be
    # overwritten. This blocks accidental reconciliation over unknown/manual
    # remote changes while keeping initial pending deployment possible.
    if ([string](Get-PPMOptional $route 'state') -eq 'deployed') {
        $current = Audit-PPMRoute -Inventory $Inventory -PrivateDirectory $privateDirectory -RouteId $RouteId
        if ([string]$current.category -ne 'in-sync') { throw 'Existing deployed Route has drift; refusing to overwrite unknown remote state.' }
    }

    $null = Invoke-PPMRouteOperation -Inventory $Inventory -RouteObject $route -PrivateDirectory $privateDirectory
    if ((Get-PPMOptional $route 'enabled' $false) -eq $false) { $route.enabled = $true }
    if ($route.PSObject.Properties['state']) { $route.state = 'deployed' } else { $route | Add-Member -NotePropertyName state -NotePropertyValue 'deployed' }
    Save-PPMInventory -Inventory $Inventory -InventoryPath $InventoryPath
    $renderArgs = @{ InventoryPath = $InventoryPath }
    if ($SkipClientValidation) { $renderArgs.SkipValidation = $true }
    $renderJson = & (Join-Path $repoRoot 'client\Render-ClientTargets.ps1') @renderArgs
    if ($LASTEXITCODE -ne 0) { throw 'Route deployed, but client rendering failed. Remote state was not rolled back.' }
    $render = $renderJson | ConvertFrom-Json
    return [ordered]@{ route = [string]$route.id; state = 'deployed'; enabled = $true; render = $render }
}

function Audit-PPMRoute {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [Parameter(Mandatory)][string]$RouteId
    )
    $route = Get-PPMRouteById -Inventory $Inventory -Id $RouteId
    try {
        $output = @(Invoke-PPMRouteOperation -Inventory $Inventory -RouteObject $route -PrivateDirectory $PrivateDirectory -AuditOnly)
        return Get-PPMAuditEvidenceFromOutput -Inventory $Inventory -Route $route -Output $output
    }
    catch {
        # Transport/preflight failures are evidence that remote state cannot be
        # determined safely, not permission to mutate. Suppress raw diagnostics.
        return [ordered]@{
            route = [string]$route.id
            status = 'undetermined'
            category = 'undetermined'
            actual_egress_ipv4 = $null
            egress_matches_declared_exit = $false
            hysteria_version = $null
            wireguard_version = $null
        }
    }
}
