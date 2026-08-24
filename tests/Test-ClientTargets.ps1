[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')
$agent = Join-Path $repo 'agent\route-steward-agent.ps1'
$renderer = Join-Path $repo 'client\Render-ClientTargets.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-targets-test-' + [Guid]::NewGuid().ToString('N'))
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
    $karingContext = [ordered]@{ target_id = 'mobile-cross-platform'; profile_id = 'primary'; renderer = 'karing' } | ConvertTo-Json -Compress
    $shadowContext = [ordered]@{ target_id = 'mobile'; profile_id = 'primary'; renderer = 'shadowrocket'; delivery = 'nodes' } | ConvertTo-Json -Compress
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $mihomoContext | ConvertFrom-Json).success) 'Explicit Mihomo ClientTarget creation failed.'
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $karingContext | ConvertFrom-Json).success) 'Explicit Karing ClientTarget creation failed.'
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $shadowContext | ConvertFrom-Json).success) 'Explicit Shadowrocket ClientTarget creation failed.'

    $inventoryPath = Join-Path $stage 'inventory.json'
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True ([string]$inventory.servers[0].compute.driver -eq 'byo-ssh') 'Server compute driver was not made explicit.'
    Assert-True ([string]$inventory.routes[0].ingress.driver -eq 'hysteria2') 'Route ingress driver was not made explicit.'
    Assert-True (-not $inventory.profiles[0].PSObject.Properties['kind']) 'Profile retained a renderer compatibility marker.'
    Assert-True ([string]$inventory.profiles[0].policy -eq '') 'Explicit Profile silently selected a geographic policy.'
    $inventory.routes[0].enabled = $true
    $inventory.routes[0].state = 'deployed'
    Save-RSTInventory -Inventory $inventory -InventoryPath $inventoryPath
    $headlessContext = [ordered]@{ target_id = 'backend'; profile_id = 'primary'; renderer = 'hysteria2'; route_id = 'direct-a'; listen = '127.0.0.1:18080'; ingress_family = 'auto' } | ConvertTo-Json -Compress
    Assert-True ((& $agent execute -PrivateDirectory $stage -Operation add-client-target -ContextJson $headlessContext | ConvertFrom-Json).success) 'Explicit Hysteria2 ClientTarget creation failed.'
    $unsafeHeadless = [ordered]@{ target_id = 'unsafe'; profile_id = 'primary'; renderer = 'hysteria2'; route_id = 'direct-a'; listen = '0.0.0.0:1080' } | ConvertTo-Json -Compress
    $unsafePreflight = & $agent preflight -PrivateDirectory $stage -Operation add-client-target -ContextJson $unsafeHeadless | ConvertFrom-Json
    Assert-True (-not $unsafePreflight.data.ready -and @($unsafePreflight.data.conflicts) -contains 'headless-listen-not-loopback') 'A public Hysteria2 listener passed preflight.'

    $privateOutput = Join-Path $stage 'private-only'
    $result = & $renderer -InventoryPath $inventoryPath -OutputDirectory $privateOutput -SkipValidation | ConvertFrom-Json
    Assert-True ($result.success -and $result.outputs.Count -eq 4) 'Rendering did not produce all explicit ClientTargets.'
    $mihomoPath = Join-Path $privateOutput 'desktop.yaml'
    $karingPath = Join-Path $privateOutput 'mobile-cross-platform.yaml'
    $shadowrocketPath = Join-Path $privateOutput 'mobile.html'
    $headlessPath = Join-Path $privateOutput 'backend.json'
    Assert-True (Test-Path -LiteralPath $mihomoPath) 'Mihomo ClientTarget output is missing.'
    Assert-True (Test-Path -LiteralPath $karingPath) 'Karing ClientTarget output is missing.'
    Assert-True (Test-Path -LiteralPath $shadowrocketPath) 'Shadowrocket ClientTarget output is missing.'
    Assert-True (Test-Path -LiteralPath $headlessPath) 'Hysteria2 ClientTarget output is missing.'

    $mihomo = [IO.File]::ReadAllText($mihomoPath, [Text.Encoding]::UTF8)
    $karing = [IO.File]::ReadAllText($karingPath, [Text.Encoding]::UTF8)
    Assert-True ($karing -ceq $mihomo) 'Karing did not reuse the tested Clash YAML contract exactly.'
    Assert-True ($karing -match '(?m)^\s+skip-cert-verify:\s*true\s*$' -and $karing -match "(?m)^\s+fingerprint:\s*'[0-9a-f]{64}'\s*$") 'Karing output weakened pinned self-signed TLS.'
    Assert-True ($mihomo -match '(?m)^\s*- name:\s*Direct-A-HY2-v[46]\s*$') 'Mihomo output is missing private Hysteria2 nodes.'
    Assert-True ($mihomo -notmatch '(?m)^proxy-providers:\s*$') 'Provider-free rendering emitted a provider section.'
    Assert-True ($mihomo -match '(?m)^\s*- MATCH,Private Routes\s*$') 'Generic private route group is missing.'
    Assert-True ($mihomo -match 'https://1\.1\.1\.1/dns-query' -and $mihomo -match 'https://8\.8\.8\.8/dns-query') 'Neutral privacy DNS defaults are missing.'
    Assert-True ($mihomo -notmatch '223\.5\.5\.5|1\.12\.12\.12|GEOSITE,CN|GEOIP,CN') 'Region-specific balanced-cn behavior leaked into the neutral default.'

    $html = [IO.File]::ReadAllText($shadowrocketPath, [Text.Encoding]::UTF8)
    Assert-True ($html -match 'Shadowrocket import' -and $html -match 'Content-Security-Policy') 'Shadowrocket output is missing its offline import shell.'
    Assert-True ($html -notmatch '(?i)<script[^>]+src=' -and $html -notmatch '(?i)\bfetch\s*\(') 'Shadowrocket output can load an external resource.'
    Assert-True ($html -match 'Direct-A-HY2-v4') 'Shadowrocket output is missing a rendered private node.'

    $headless = [IO.File]::ReadAllText($headlessPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert-True ([string]$headless.server -eq '192.0.2.10:443') 'Hysteria2 auto mode did not deterministically select IPv4.'
    Assert-True ([string]$headless.http.listen -eq '127.0.0.1:18080' -and [string]$headless.socks5.listen -eq '127.0.0.1:18080') 'Hysteria2 HTTP/SOCKS5 listeners are not the target loopback listener.'
    Assert-True ($headless.tls.insecure -eq $true -and [string]$headless.tls.pinSHA256 -match '^[0-9a-f]{64}$') 'Hysteria2 output did not retain pinned TLS verification.'

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

    Write-Host 'Explicit Mihomo/Karing/Shadowrocket/headless ClientTargets, pinned Karing import, neutral defaults, and Provider composition tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
