[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\PrivateProxyManager.Core.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Model.ps1')
$agent = Join-Path $repo 'agent\ppm-agent.ps1'
$renderer = Join-Path $repo 'client\Render-ClientTargets.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('ppm-targets-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $bootstrap = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    Assert-True ($bootstrap.data.context.inventory_schema -eq 1) 'Clean bootstrap did not create public schema 1.'
    Assert-True (@($bootstrap.data.context.client_targets).Count -eq 0) 'Clean bootstrap assumed a client app or device.'
    Assert-True (@($bootstrap.data.context.profiles).Count -eq 0) 'Clean bootstrap assumed a Profile or policy.'

    $keyPath = Join-Path $stage 'fixture.pem'
    [IO.File]::WriteAllText($keyPath, 'fixture', [Text.UTF8Encoding]::new($false))
    $serverContext = [ordered]@{ server_id = 'entry-a'; public_ipv4 = '192.0.2.10'; public_ipv6 = '2001:db8::10'; ssh_user = 'ubuntu'; ssh_key_path = $keyPath; host_ownership = 'dedicated' } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-server -ContextJson $serverContext | ConvertFrom-Json
    $routeContext = [ordered]@{ route_id = 'direct-a'; display_name = 'Direct-A'; kind = 'direct'; entry_server = 'entry-a'; listen_port = 443 } | ConvertTo-Json -Compress
    $null = & $agent execute -PrivateDirectory $stage -Operation add-route -ContextJson $routeContext | ConvertFrom-Json
    $profileContext = [ordered]@{ profile_id = 'primary'; include_routes = @('direct-a'); include_providers = @() } | ConvertTo-Json -Compress
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-profile -ContextJson $profileContext | ConvertFrom-Json).success) 'Explicit Profile creation failed.'
    $mihomoContext = [ordered]@{ target_id = 'desktop'; profile_id = 'primary'; renderer = 'mihomo' } | ConvertTo-Json -Compress
    $shadowContext = [ordered]@{ target_id = 'mobile'; profile_id = 'primary'; renderer = 'shadowrocket'; delivery = 'nodes' } | ConvertTo-Json -Compress
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $mihomoContext | ConvertFrom-Json).success) 'Explicit Mihomo ClientTarget creation failed.'
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $shadowContext | ConvertFrom-Json).success) 'Explicit Shadowrocket ClientTarget creation failed.'

    $inventoryPath = Join-Path $stage 'inventory.json'
    $inventory = Read-PPMInventory -Path $inventoryPath
    Assert-True ([string]$inventory.servers[0].compute.driver -eq 'byo-ssh') 'Server compute driver was not made explicit.'
    Assert-True ([string]$inventory.routes[0].ingress.driver -eq 'hysteria2') 'Route ingress driver was not made explicit.'
    Assert-True (-not $inventory.profiles[0].PSObject.Properties['kind']) 'Profile retained a renderer compatibility marker.'
    Assert-True ([string]$inventory.profiles[0].policy -eq '') 'Explicit Profile silently selected a geographic policy.'
    $inventory.routes[0].enabled = $true
    $inventory.routes[0].state = 'deployed'
    Save-PPMInventory -Inventory $inventory -InventoryPath $inventoryPath

    $privateOutput = Join-Path $stage 'private-only'
    $result = & $renderer -InventoryPath $inventoryPath -OutputDirectory $privateOutput -SkipValidation | ConvertFrom-Json
    Assert-True ($result.success -and $result.outputs.Count -eq 2) 'Rendering did not produce both explicit ClientTargets.'
    $mihomoPath = Join-Path $privateOutput 'desktop.yaml'
    $shadowrocketPath = Join-Path $privateOutput 'mobile.html'
    Assert-True (Test-Path -LiteralPath $mihomoPath) 'Mihomo ClientTarget output is missing.'
    Assert-True (Test-Path -LiteralPath $shadowrocketPath) 'Shadowrocket ClientTarget output is missing.'

    $mihomo = [IO.File]::ReadAllText($mihomoPath, [Text.Encoding]::UTF8)
    Assert-True ($mihomo -match '(?m)^\s*- name:\s*Direct-A-HY2-v[46]\s*$') 'Mihomo output is missing private Hysteria2 nodes.'
    Assert-True ($mihomo -notmatch '(?m)^proxy-providers:\s*$') 'Provider-free rendering emitted a provider section.'
    Assert-True ($mihomo -match '(?m)^\s*- MATCH,Private Routes\s*$') 'Generic private route group is missing.'
    Assert-True ($mihomo -match 'https://1\.1\.1\.1/dns-query' -and $mihomo -match 'https://8\.8\.8\.8/dns-query') 'Neutral privacy DNS defaults are missing.'
    Assert-True ($mihomo -notmatch '223\.5\.5\.5|1\.12\.12\.12|GEOSITE,CN|GEOIP,CN') 'Region-specific balanced-cn behavior leaked into the neutral default.'

    $html = [IO.File]::ReadAllText($shadowrocketPath, [Text.Encoding]::UTF8)
    Assert-True ($html -match 'Shadowrocket import' -and $html -match 'Content-Security-Policy') 'Shadowrocket output is missing its offline import shell.'
    Assert-True ($html -notmatch '(?i)<script[^>]+src=' -and $html -notmatch '(?i)\bfetch\s*\(') 'Shadowrocket output can load an external resource.'
    Assert-True ($html -match 'Direct-A-HY2-v4') 'Shadowrocket output is missing a rendered private node.'

    $providerContext = [ordered]@{ provider_id = 'example-provider'; display_name = 'Example Provider'; url = 'https://example.invalid/provider.yaml'; interval_seconds = 86400 } | ConvertTo-Json -Compress
    $provider = & $agent execute -PrivateDirectory $stage -Operation add-provider -ContextJson $providerContext | ConvertFrom-Json
    Assert-True ($provider.success -and $provider.data.result.source_type -eq 'mihomo-http') 'Generic Provider was not added through the Agent contract.'
    $profileUpdate = [ordered]@{ include_providers = @('example-provider') } | ConvertTo-Json -Compress
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation update-profile -Target primary -ContextJson $profileUpdate | ConvertFrom-Json).success) 'Profile could not select the generic Provider.'

    $providerOutput = Join-Path $stage 'with-provider'
    $providerResult = & $renderer -InventoryPath $inventoryPath -ClientTargetId desktop -OutputDirectory $providerOutput -SkipValidation | ConvertFrom-Json
    Assert-True ($providerResult.outputs[0].provider_count -eq 1) 'Generic Provider was not composed into the Mihomo ClientTarget.'
    $providerMihomo = [IO.File]::ReadAllText((Join-Path $providerOutput 'desktop.yaml'), [Text.Encoding]::UTF8)
    Assert-True ($providerMihomo -match '(?m)^proxy-providers:\s*$' -and $providerMihomo -match '(?m)^\s{2}example-provider:\s*$') 'Generic Provider block is missing.'

    Write-Host 'Explicit Profile/ClientTarget separation, neutral rendering, driver fields, and optional Provider composition tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
