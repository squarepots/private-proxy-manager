$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RSTOptional {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) {
        if (-not $Object.Contains($Name) -or $null -eq $Object[$Name]) { return $Default }
        if ($Object[$Name] -is [string] -and [string]::IsNullOrWhiteSpace([string]$Object[$Name])) { return $Default }
        return $Object[$Name]
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    if ($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)) { return $Default }
    return $property.Value
}

function ConvertTo-RSTId {
    param([Parameter(Mandatory)][string]$Value)
    $normalized = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $normalized = $normalized.Trim('-')
    if (-not $normalized) { throw 'A stable ID could not be derived from the supplied name.' }
    return $normalized
}

function Resolve-RSTPath {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$BaseDirectory)
    if ([IO.Path]::IsPathRooted($Value)) { return [IO.Path]::GetFullPath($Value) }
    return [IO.Path]::GetFullPath((Join-Path $BaseDirectory $Value))
}

function Protect-RSTPath {
    param([Parameter(Mandatory)][string]$Path, [switch]$Directory)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Cannot protect a private path that does not exist.' }
    if ($env:OS -eq 'Windows_NT') {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $Path '/inheritance:r' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove inherited permissions from a private path.' }
        $grant = if ($Directory) { '{0}:(OI)(CI)F' -f $identity } else { '{0}:F' -f $identity }
        & icacls.exe $Path '/grant:r' $grant | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not restrict a private path to the current user.' }
        return
    }
    $chmod = Get-Command chmod -ErrorAction SilentlyContinue
    if (-not $chmod) { throw 'chmod is required to protect private state on this platform.' }
    $mode = if ($Directory) { '700' } else { '600' }
    & $chmod.Source $mode -- $Path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict a private path to the current user.' }
}

function Test-RSTPrivateAcl {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ($env:OS -eq 'Windows_NT') {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl = Get-Acl -LiteralPath $Path
        $allowRules = @($acl.Access | Where-Object { $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow })
        if (-not $allowRules.Count) { return $false }
        if (@($allowRules | Where-Object { $_.IsInherited -or $_.IdentityReference.Value -ne $identity }).Count) { return $false }
        return $true
    }
    try {
        $mode = [IO.File]::GetUnixFileMode([IO.Path]::GetFullPath($Path))
        $disallowed = [IO.UnixFileMode]::GroupRead -bor [IO.UnixFileMode]::GroupWrite -bor [IO.UnixFileMode]::GroupExecute -bor [IO.UnixFileMode]::OtherRead -bor [IO.UnixFileMode]::OtherWrite -bor [IO.UnixFileMode]::OtherExecute
        return (($mode -band $disallowed) -eq 0)
    }
    catch { return $false }
}

function Write-RSTJsonAtomic {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path, [int]$Depth = 30)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    Protect-RSTPath -Path $directory -Directory
    $temporary = Join-Path $directory ('.' + [IO.Path]::GetFileName($fullPath) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth $Depth), [Text.UTF8Encoding]::new($false))
        Protect-RSTPath -Path $temporary
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force
        Protect-RSTPath -Path $fullPath
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Test-RSTIPv4 {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $parsed = $null
    return [Net.IPAddress]::TryParse($Value, [ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
}

function Test-RSTIPv6 {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $parsed = $null
    return [Net.IPAddress]::TryParse($Value, [ref]$parsed) -and $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
}

function Test-RSTLoopbackListener {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $match = [regex]::Match($Value, '^(?:\[(?<ipv6>[^\]]+)\]|(?<ipv4>[^:]+)):(?<port>\d+)$')
    if (-not $match.Success) { return $false }
    $hostName = if ($match.Groups['ipv6'].Success) { $match.Groups['ipv6'].Value } else { $match.Groups['ipv4'].Value }
    $address = $null
    if (-not [Net.IPAddress]::TryParse($hostName, [ref]$address) -or -not [Net.IPAddress]::IsLoopback($address)) { return $false }
    $port = 0
    return [int]::TryParse($match.Groups['port'].Value, [ref]$port) -and $port -ge 1 -and $port -le 65535
}

function Test-RSTUnixUser {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return $Value -cmatch '^[a-z_][a-z0-9_-]{0,31}$'
}

function Read-RSTJson {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label was not found." }
    try { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { throw "$Label is not valid JSON." }
}

function Read-RSTSecretIndex {
    param([Parameter(Mandatory)][string]$PrivateDirectory)
    $path = Join-Path $PrivateDirectory 'secrets\index.json'
    $index = Read-RSTJson -Path $path -Label 'The private secret index'
    if ([int](Get-RSTOptional $index 'schema' 0) -ne 1 -or $null -eq $index.refs) {
        throw 'The private secret index does not match schema 1.'
    }
    return $index
}

function Resolve-RSTSecret {
    param(
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        $Index
    )
    if (-not $Index) { $Index = Read-RSTSecretIndex -PrivateDirectory $PrivateDirectory }
    $property = $Index.refs.PSObject.Properties[$Reference]
    if ($null -eq $property) { throw "Secret reference '$Reference' is not registered." }
    $relative = [string](Get-RSTOptional $property.Value 'path')
    if (-not $relative -or [IO.Path]::IsPathRooted($relative)) { throw "Secret reference '$Reference' has an invalid path." }
    $root = [IO.Path]::GetFullPath((Join-Path $PrivateDirectory 'secrets'))
    $resolved = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $resolved.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Secret reference '$Reference' leaves the private secret directory."
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Secret reference '$Reference' is missing." }
    return $resolved
}

function Get-RSTDefaultPolicies {
    return @(
        [ordered]@{
            id = 'balanced-cn'
            description = 'LAN and China direct; overseas DNS follows the selected route.'
            dns_mode = 'balanced-cn'
        },
        [ordered]@{
            id = 'privacy'
            description = 'Ordinary DNS follows the selected route; domestic CDN performance may be lower.'
            dns_mode = 'privacy'
        }
    )
}

function Assert-RSTInventory {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$PrivateDirectory, [switch]$SkipSecretCheck)
    $failures = [Collections.Generic.List[string]]::new()
    if ([int](Get-RSTOptional $Inventory 'schema' 0) -ne 1) { $failures.Add('Inventory schema must be 1.') }

    $servers = @(Get-RSTOptional $Inventory 'servers' @())
    $links = @(Get-RSTOptional $Inventory 'links' @())
    $routes = @(Get-RSTOptional $Inventory 'routes' @())
    $providers = @(Get-RSTOptional $Inventory 'providers' @())
    $policies = @(Get-RSTOptional $Inventory 'policies' @())
    $profiles = @(Get-RSTOptional $Inventory 'profiles' @())
    $clientTargets = @(Get-RSTOptional $Inventory 'client_targets' @())

    foreach ($collection in @(
        [pscustomobject]@{ Name = 'Server'; Values = $servers },
        [pscustomobject]@{ Name = 'Link'; Values = $links },
        [pscustomobject]@{ Name = 'Route'; Values = $routes },
        [pscustomobject]@{ Name = 'Provider'; Values = $providers },
        [pscustomobject]@{ Name = 'Policy'; Values = $policies },
        [pscustomobject]@{ Name = 'Profile'; Values = $profiles },
        [pscustomobject]@{ Name = 'ClientTarget'; Values = $clientTargets }
    )) {
        $ids = @($collection.Values | ForEach-Object { [string](Get-RSTOptional $_ 'id') })
        if ($ids -contains '') { $failures.Add("$($collection.Name) IDs are required.") }
        if ($ids.Count -ne @($ids | Sort-Object -Unique).Count) { $failures.Add("$($collection.Name) IDs must be unique.") }
        foreach ($id in $ids) { if ($id -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { $failures.Add("$($collection.Name) ID '$id' is invalid.") } }
    }

    $serverById = @{}
    foreach ($server in $servers) {
        $id = [string]$server.id
        $serverById[$id] = $server
        $compute = Get-RSTOptional $server 'compute'
        if ([string](Get-RSTOptional $compute 'driver') -ne 'byo-ssh') {
            $failures.Add("Server '$id' must declare compute.driver=byo-ssh.")
        }
        if ([string](Get-RSTOptional $compute 'host_ownership') -ne 'dedicated') {
            $failures.Add("Server '$id' must declare compute.host_ownership=dedicated.")
        }
        $network = Get-RSTOptional $server 'network'
        $publicV4 = [string](Get-RSTOptional $network 'public_ipv4')
        $publicV6 = [string](Get-RSTOptional $network 'public_ipv6')
        $privateV4 = [string](Get-RSTOptional $network 'private_ipv4')
        $egressV4 = [string](Get-RSTOptional $network 'expected_egress_ipv4')
        if ($publicV4 -and -not (Test-RSTIPv4 $publicV4)) { $failures.Add("Server '$id' has an invalid public IPv4.") }
        if ($privateV4 -and -not (Test-RSTIPv4 $privateV4)) { $failures.Add("Server '$id' has an invalid private IPv4.") }
        if ($publicV6 -and -not (Test-RSTIPv6 $publicV6)) { $failures.Add("Server '$id' has an invalid public IPv6.") }
        if ($egressV4 -and -not (Test-RSTIPv4 $egressV4)) { $failures.Add("Server '$id' has an invalid expected egress IPv4.") }
        $ssh = Get-RSTOptional $server 'ssh'
        $sshUser = [string](Get-RSTOptional $ssh 'user')
        if (-not $sshUser -or -not (Get-RSTOptional $ssh 'key_path')) {
            $failures.Add("Server '$id' must have an SSH user and key path.")
        }
        elseif (-not (Test-RSTUnixUser $sshUser)) { $failures.Add("Server '$id' has an invalid SSH user.") }
    }

    foreach ($server in $servers) {
        $seenFirewallRules = @{}
        foreach ($rule in @(Get-RSTOptional (Get-RSTOptional $server 'firewall') 'rules' @())) {
            $family = [string](Get-RSTOptional $rule 'family')
            $protocol = [string](Get-RSTOptional $rule 'protocol')
            $port = [int](Get-RSTOptional $rule 'port' 0)
            $sourceServer = [string](Get-RSTOptional $rule 'source_server')
            $source = [string](Get-RSTOptional $rule 'source')
            if ($family -notin @('ipv4', 'ipv6', 'dual')) { $failures.Add("Server '$($server.id)' has an invalid firewall family.") }
            if ($protocol -notin @('tcp', 'udp')) { $failures.Add("Server '$($server.id)' has an invalid firewall protocol.") }
            if ($port -lt 1 -or $port -gt 65535) { $failures.Add("Server '$($server.id)' has an invalid firewall port.") }
            if (-not $source -and -not $sourceServer) { $failures.Add("Server '$($server.id)' has a firewall rule without a source.") }
            if ($sourceServer -and -not $serverById.ContainsKey($sourceServer)) { $failures.Add("Server '$($server.id)' firewall references unknown source Server '$sourceServer'.") }
            $key = '{0}:{1}:{2}:{3}' -f $family, $protocol, $port, $(if ($sourceServer) { "server:$sourceServer" } else { $source })
            if ($seenFirewallRules.ContainsKey($key)) { $failures.Add("Server '$($server.id)' has duplicate firewall rule '$key'.") } else { $seenFirewallRules[$key] = $true }
        }
    }

    $linkById = @{}
    $interfaces = @{}
    $ports = @{}
    $subnets = @{}
    foreach ($link in $links) {
        $id = [string]$link.id
        $linkById[$id] = $link
        if ([string](Get-RSTOptional $link 'type') -ne 'wireguard') { $failures.Add("Link '$id' must use WireGuard.") }
        if ([string](Get-RSTOptional $link 'driver') -ne 'wireguard') { $failures.Add("Link '$id' must declare driver=wireguard.") }
        foreach ($endpoint in 'entry_server', 'exit_server') {
            $serverId = [string](Get-RSTOptional $link $endpoint)
            if (-not $serverById.ContainsKey($serverId)) { $failures.Add("Link '$id' references unknown $endpoint '$serverId'.") }
        }
        $interface = [string](Get-RSTOptional $link 'interface')
        $port = [int](Get-RSTOptional $link 'listen_port' 0)
        $subnet = [string](Get-RSTOptional $link 'subnet')
        if ($interface -notmatch '^[a-z0-9][a-z0-9_-]{0,14}$') { $failures.Add("Link '$id' has an invalid interface.") }
        if ($port -lt 1 -or $port -gt 65535) { $failures.Add("Link '$id' has an invalid UDP port.") }
        if ($subnet -notmatch '^10\.77\.(?:[0-9]|[1-9][0-9]|[12][0-9]{2})\.0/30$') { $failures.Add("Link '$id' has an invalid /30 subnet.") }
        foreach ($pair in @(@($interfaces, $interface, 'interface'), @($ports, [string]$port, 'port'), @($subnets, $subnet, 'subnet'))) {
            $map = $pair[0]; $value = [string]$pair[1]; $label = [string]$pair[2]
            if ($map.ContainsKey($value)) { $failures.Add("Links '$id' and '$($map[$value])' share $label '$value'.") } else { $map[$value] = $id }
        }
    }

    $routeListeners = @{}
    $directEntries = @{}
    foreach ($route in $routes) {
        $id = [string]$route.id
        $kind = [string](Get-RSTOptional $route 'kind')
        if ($kind -notin @('direct', 'relay')) { $failures.Add("Route '$id' has unsupported kind '$kind'.") }
        if ([string](Get-RSTOptional (Get-RSTOptional $route 'ingress') 'driver') -ne 'hysteria2') {
            $failures.Add("Route '$id' must declare ingress.driver=hysteria2.")
        }
        $entry = [string](Get-RSTOptional $route 'entry_server')
        $exit = [string](Get-RSTOptional $route 'exit_server')
        if (-not $serverById.ContainsKey($entry)) { $failures.Add("Route '$id' references unknown entry Server '$entry'.") }
        if (-not $serverById.ContainsKey($exit)) { $failures.Add("Route '$id' references unknown exit Server '$exit'.") }
        $port = [int](Get-RSTOptional $route 'listen_port' 0)
        if ($port -lt 1 -or $port -gt 65535) { $failures.Add("Route '$id' has an invalid HY2 port.") }
        $listenerKey = '{0}:{1}' -f $entry, $port
        if ($routeListeners.ContainsKey($listenerKey)) { $failures.Add("Routes '$id' and '$($routeListeners[$listenerKey])' share listener '$listenerKey'.") }
        else { $routeListeners[$listenerKey] = $id }
        if ($kind -eq 'relay') {
            $linkId = [string](Get-RSTOptional $route 'link')
            if (-not $linkById.ContainsKey($linkId)) { $failures.Add("Relay Route '$id' references unknown Link '$linkId'.") }
            elseif ($linkById[$linkId].entry_server -ne $entry -or $linkById[$linkId].exit_server -ne $exit) { $failures.Add("Relay Route '$id' does not match Link '$linkId' endpoints.") }
        }
        elseif ($kind -eq 'direct') {
            if ($directEntries.ContainsKey($entry)) { $failures.Add("Direct Routes '$id' and '$($directEntries[$entry])' share one entry Server service.") }
            else { $directEntries[$entry] = $id }
        }
        if (-not (Get-RSTOptional $route 'payload_secret_ref')) { $failures.Add("Route '$id' is missing its payload secret reference.") }
    }

    $providerIds = @($providers | ForEach-Object { [string]$_.id })
    foreach ($provider in $providers) {
        $id = [string]$provider.id
        if ([string](Get-RSTOptional $provider 'source_type') -ne 'mihomo-http') { $failures.Add("Provider '$id' must declare source_type=mihomo-http.") }
        if (-not (Get-RSTOptional $provider 'source_secret_ref')) { $failures.Add("Provider '$id' is missing source_secret_ref.") }
        if ([int](Get-RSTOptional $provider 'interval_seconds' 0) -lt 3600) { $failures.Add("Provider '$id' refresh interval must be at least one hour.") }
        if ((Get-RSTOptional $provider 'health_check' $false) -ne $false) { $failures.Add("Provider '$id' must not enable automatic health checking.") }
    }

    $policyIds = @($policies | ForEach-Object { [string]$_.id })
    $routeIds = @($routes | ForEach-Object { [string]$_.id })
    $profileIds = @($profiles | ForEach-Object { [string]$_.id })
    foreach ($profile in $profiles) {
        $id = [string]$profile.id
        $policy = [string](Get-RSTOptional $profile 'policy')
        if ($policy -and $policyIds -notcontains $policy) { $failures.Add("Profile '$id' references unknown Policy '$policy'.") }
        foreach ($routeId in @(Get-RSTOptional $profile 'include_routes' @('*'))) {
            if ($routeId -ne '*' -and $routeIds -notcontains [string]$routeId) { $failures.Add("Profile '$id' references unknown Route '$routeId'.") }
        }
        foreach ($providerId in @(Get-RSTOptional $profile 'include_providers' @())) {
            if ($providerId -ne '*' -and $providerIds -notcontains [string]$providerId) { $failures.Add("Profile '$id' references unknown Provider '$providerId'.") }
        }
    }

    foreach ($target in $clientTargets) {
        $id = [string]$target.id
        $profileId = [string](Get-RSTOptional $target 'profile')
        $renderer = [string](Get-RSTOptional $target 'renderer')
        $delivery = [string](Get-RSTOptional $target 'delivery')
        $subscriptionRef = [string](Get-RSTOptional $target 'subscription_secret_ref')
        if ($profileIds -notcontains $profileId) { $failures.Add("ClientTarget '$id' references unknown Profile '$profileId'.") }
        if ($renderer -notin @('mihomo','shadowrocket','hysteria2')) { $failures.Add("ClientTarget '$id' has unsupported renderer '$renderer'.") }
        if ($renderer -eq 'mihomo') {
            if ($delivery -ne 'file') { $failures.Add("Mihomo ClientTarget '$id' must use file delivery.") }
            if ($subscriptionRef) { $failures.Add("Mihomo ClientTarget '$id' cannot own subscription state.") }
        }
        if ($renderer -eq 'shadowrocket') {
            if ($delivery -notin @('nodes','subscription')) { $failures.Add("Shadowrocket ClientTarget '$id' has unsupported delivery '$delivery'.") }
            if ($delivery -eq 'subscription' -and -not $subscriptionRef) { $failures.Add("Shadowrocket ClientTarget '$id' requires subscription_secret_ref for subscription delivery.") }
            if ($subscriptionRef -and $delivery -ne 'subscription') { $failures.Add("Shadowrocket ClientTarget '$id' with subscription state must use subscription delivery.") }
        }
        if ($renderer -eq 'hysteria2') {
            $routeId = [string](Get-RSTOptional $target 'route')
            $listen = [string](Get-RSTOptional $target 'listen')
            $family = [string](Get-RSTOptional $target 'ingress_family')
            $selectedRoute = @($routes | Where-Object id -eq $routeId)
            $selectedProfile = @($profiles | Where-Object id -eq $profileId)
            if ($delivery -ne 'file' -or $subscriptionRef) { $failures.Add("Hysteria2 ClientTarget '$id' must use private file delivery.") }
            if ($selectedRoute.Count -ne 1 -or (Get-RSTOptional $selectedRoute[0] 'enabled' $true) -eq $false) { $failures.Add("Hysteria2 ClientTarget '$id' must select one enabled Route.") }
            elseif ($selectedProfile.Count -eq 1) {
                $included = @(Get-RSTOptional $selectedProfile[0] 'include_routes' @('*'))
                if ($included -notcontains '*' -and $included -notcontains $routeId) { $failures.Add("Hysteria2 ClientTarget '$id' selects a Route outside its Profile.") }
            }
            if (-not (Test-RSTLoopbackListener $listen)) { $failures.Add("Hysteria2 ClientTarget '$id' must use a loopback listener.") }
            if ($family -notin @('auto','ipv4','ipv6')) { $failures.Add("Hysteria2 ClientTarget '$id' has an invalid ingress family.") }
        }
    }

    if (-not $SkipSecretCheck) {
        try {
            $secretIndex = Read-RSTSecretIndex -PrivateDirectory $PrivateDirectory
            $references = @()
            $references += $providers | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | ForEach-Object { Get-RSTOptional $_ 'source_secret_ref' }
            $references += $routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | ForEach-Object { Get-RSTOptional $_ 'payload_secret_ref' }
            $references += $routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | ForEach-Object { Get-RSTOptional $_ 'credential_secret_ref' }
            $references += $links | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | ForEach-Object { Get-RSTOptional $_ 'secret_ref' }
            $references += $clientTargets | ForEach-Object { Get-RSTOptional $_ 'subscription_secret_ref' }
            foreach ($reference in @($references | Where-Object { $_ } | Sort-Object -Unique)) {
                try { $null = Resolve-RSTSecret -Reference $reference -PrivateDirectory $PrivateDirectory -Index $secretIndex }
                catch { $failures.Add($_.Exception.Message) }
            }
        }
        catch { $failures.Add($_.Exception.Message) }
    }

    if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
    return $true
}

function Read-RSTInventory {
    param([Parameter(Mandatory)][string]$Path, [switch]$SkipSecretCheck)
    $inventory = Read-RSTJson -Path $Path -Label 'The private inventory'
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    $null = Assert-RSTInventory -Inventory $inventory -PrivateDirectory $privateDirectory -SkipSecretCheck:$SkipSecretCheck
    return $inventory
}

function New-RSTLinkAllocation {
    param([Parameter(Mandatory)]$Inventory)
    $usedInterfaces = @(@(Get-RSTOptional $Inventory 'links' @()) | ForEach-Object { [string]$_.interface })
    $usedPorts = @(@(Get-RSTOptional $Inventory 'links' @()) | ForEach-Object { [int]$_.listen_port })
    $usedSubnets = @(@(Get-RSTOptional $Inventory 'links' @()) | ForEach-Object { [string]$_.subnet })
    for ($slot = 1; $slot -le 99; $slot++) {
        $interface = 'wg-rst{0:d2}' -f $slot
        $port = 51819 + $slot
        $subnet = '10.77.{0}.0/30' -f $slot
        if ($usedInterfaces -notcontains $interface -and $usedPorts -notcontains $port -and $usedSubnets -notcontains $subnet) {
            return [pscustomobject]@{ slot = $slot; interface = $interface; listen_port = $port; subnet = $subnet }
        }
    }
    throw 'No free relay slot remains in the supported 1..99 range.'
}

function Get-RSTServerById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id)
    $matches = @($Inventory.servers | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Unknown Server '$Id'." }
    return $matches[0]
}

function Get-RSTLinkById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id)
    $matches = @($Inventory.links | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Unknown Link '$Id'." }
    return $matches[0]
}

function Get-RSTRouteById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id)
    $matches = @($Inventory.routes | Where-Object { $_.id -eq $Id -or $_.display_name -eq $Id })
    if ($matches.Count -ne 1) { throw "Unknown Route '$Id'." }
    return $matches[0]
}

function Get-RSTProfileById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id)
    $matches = @($Inventory.profiles | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Unknown Profile '$Id'." }
    return $matches[0]
}

function Get-RSTPolicyById {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$Id)
    $matches = @($Inventory.policies | Where-Object { $_.id -eq $Id })
    if ($matches.Count -ne 1) { throw "Unknown Policy '$Id'." }
    return $matches[0]
}
