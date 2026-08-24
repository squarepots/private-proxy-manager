[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InventoryPath,
    [Alias('ProfileId')][string]$ClientTargetId,
    [string]$OutputDirectory,
    [string]$MihomoPath,
    [switch]$SkipValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')

function ConvertFrom-YamlScalar {
    param([Parameter(Mandatory)][string]$Value)
    $value = $Value.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") { return $value.Substring(1, $value.Length - 2).Replace("''", "'") }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') { return ($value | ConvertFrom-Json) }
    return $value
}

function ConvertTo-YamlSingleQuoted {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-NodeValue {
    param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Key, [switch]$Required)
    $match = [regex]::Match($Body, '(?m)^\s{4,10}' + [regex]::Escape($Key) + ':\s*(?<value>.*?)\s*$')
    if (-not $match.Success) { if ($Required) { throw "A node is missing required field '$Key'." }; return $null }
    return ConvertFrom-YamlScalar $match.Groups['value'].Value
}

function ConvertTo-UriComponent { param([Parameter(Mandatory)][AllowEmptyString()][string]$Value) return [Uri]::EscapeDataString($Value) }
function Format-UriHost { param([Parameter(Mandatory)][string]$Address) if ($Address.Contains(':')) { return "[$Address]" }; return $Address }

function ConvertTo-NormalizedFingerprint {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$NodeName)
    $normalized = ($Value -replace '[:\s-]', '').ToLowerInvariant()
    if ($normalized -notmatch '^[0-9a-f]{64}$') { throw "Node '$NodeName' does not contain a valid SHA-256 certificate fingerprint." }
    return $normalized
}

function ConvertTo-ShadowrocketUri {
    param([Parameter(Mandatory)]$Node)
    $type = Get-NodeValue -Body $Node.Body -Key 'type' -Required
    if ($type.ToLowerInvariant() -ne 'hysteria2') { throw "Node '$($Node.Name)' uses unsupported type '$type'." }
    $server = Get-NodeValue -Body $Node.Body -Key 'server' -Required
    $port = Get-NodeValue -Body $Node.Body -Key 'port' -Required
    $auth = Get-NodeValue -Body $Node.Body -Key 'password' -Required
    $sni = Get-NodeValue -Body $Node.Body -Key 'sni' -Required
    $fingerprint = ConvertTo-NormalizedFingerprint -Value (Get-NodeValue -Body $Node.Body -Key 'fingerprint' -Required) -NodeName $Node.Name
    $obfs = Get-NodeValue -Body $Node.Body -Key 'obfs' -Required
    $obfsPassword = Get-NodeValue -Body $Node.Body -Key 'obfs-password' -Required
    if ($obfs -ne 'salamander') { throw "Node '$($Node.Name)' uses unsupported Hysteria2 obfuscation." }
    $query = @(
        'auth=' + (ConvertTo-UriComponent $auth),
        'obfs=' + (ConvertTo-UriComponent $obfs),
        'obfs-password=' + (ConvertTo-UriComponent $obfsPassword),
        'obfsParam=' + (ConvertTo-UriComponent $obfsPassword),
        'sni=' + (ConvertTo-UriComponent $sni),
        'peer=' + (ConvertTo-UriComponent $sni),
        'alpn=h3','udp=1','insecure=1','pinSHA256=' + $fingerprint
    ) -join '&'
    return 'hysteria2://{0}@{1}:{2}/?{3}#{4}' -f (ConvertTo-UriComponent $auth), (Format-UriHost $server), $port, $query, (ConvertTo-UriComponent $Node.Name)
}

function Read-RouteNodes {
    param([Parameter(Mandatory)][string[]]$PayloadPaths)
    $nodes = [Collections.Generic.List[object]]::new()
    $rawBodies = [Collections.Generic.List[string]]::new()
    foreach ($path in $PayloadPaths) {
        $raw = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $path).Path, [Text.Encoding]::UTF8)
        if ($raw -notmatch '(?m)^schema:\s*1\s*$' -or $raw -notmatch '(?ms)^proxies:\s*\r?\n(?<nodes>.+)\z') { throw 'Every route payload must be a RST schema 1 client payload.' }
        $nodeBody = $Matches.nodes.TrimEnd()
        $blocks = [regex]::Matches($nodeBody, '(?ms)^\s{2}- name:\s*(?<name>[^\r\n]+)\r?\n(?<body>.*?)(?=^\s{2}- name:|\z)')
        if ($blocks.Count -lt 1) { throw 'A route payload contains no proxy nodes.' }
        foreach ($block in $blocks) {
            $name = ConvertFrom-YamlScalar $block.Groups['name'].Value
            $node = [pscustomobject]@{ Name = $name; Body = $block.Groups['body'].Value }
            if ((Get-NodeValue -Body $node.Body -Key 'type' -Required).ToLowerInvariant() -ne 'hysteria2') { throw "Private node '$name' must use Hysteria2 in the current renderer." }
            $nodes.Add($node)
        }
        $rawBodies.Add($nodeBody)
    }
    return [pscustomobject]@{ Nodes = @($nodes); Bodies = @($rawBodies) }
}

function Get-ProfileRoutePayloads {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$PrivateDirectory)
    $include = @(Get-RSTOptional $Profile 'include_routes' @('*'))
    $routes = @($Inventory.routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | Sort-Object order)
    if ($include -notcontains '*') { $routes = @($routes | Where-Object { $include -contains $_.id }) }
    if (-not $routes.Count) { throw "Profile '$($Profile.id)' has no enabled Routes." }
    return @($routes | ForEach-Object {
        $driver = [string](Get-RSTOptional (Get-RSTOptional $_ 'ingress') 'driver' 'hysteria2')
        if ($driver -ne 'hysteria2') { throw "Route '$($_.id)' uses unsupported ingress driver '$driver' for this renderer." }
        Resolve-RSTSecret -Reference ([string]$_.payload_secret_ref) -PrivateDirectory $PrivateDirectory
    })
}

function Get-ProfileProviders {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][string]$PrivateDirectory)
    $include = @(Get-RSTOptional $Profile 'include_providers' @())
    if (-not $include.Count) { return @() }
    $providers = @($Inventory.providers | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false })
    if ($include -notcontains '*') { $providers = @($providers | Where-Object { $include -contains $_.id }) }
    return @($providers | ForEach-Object {
        $sourceType = [string](Get-RSTOptional $_ 'source_type')
        if ($sourceType -ne 'mihomo-http') { throw "Provider '$($_.id)' source type '$sourceType' is unsupported by the Mihomo renderer." }
        $reference = [string](Get-RSTOptional $_ 'source_secret_ref')
        $urlPath = Resolve-RSTSecret -Reference $reference -PrivateDirectory $PrivateDirectory
        $url = [IO.File]::ReadAllText($urlPath, [Text.Encoding]::UTF8).Trim()
        $uri = $null
        if ($url -match '[\r\n]' -or -not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https')) { throw "Provider '$($_.id)' URL is invalid." }
        [pscustomobject]@{ Id = [string]$_.id; Name = [string](Get-RSTOptional $_ 'display_name' $_.id); Url = $url; Interval = [int](Get-RSTOptional $_ 'interval_seconds' 86400) }
    })
}

function Get-DnsYaml {
    param([Parameter(Mandatory)][string]$Policy)
    $policyBlock = if ($Policy -eq 'balanced-cn') { "  nameserver-policy:`n    'geosite:private,cn':`n      - https://223.5.5.5/dns-query`n      - https://1.12.12.12/dns-query`n" } else { '' }
    return @"
dns:
  enable: true
  ipv6: true
  listen: 0.0.0.0:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-system-hosts: false
  respect-rules: true
  default-nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  nameserver:
    - 'https://1.1.1.1/dns-query#Private Routes'
    - 'https://8.8.8.8/dns-query#Private Routes'
$policyBlock
"@
}

function Get-PolicyRulesYaml {
    param([Parameter(Mandatory)][string]$Policy)
    if ($Policy -eq 'balanced-cn') {
        return "  - DOMAIN-SUFFIX,cn,DIRECT`n  - GEOSITE,CN,DIRECT`n  - GEOIP,CN,DIRECT,no-resolve`n"
    }
    return ''
}

function Resolve-MihomoCore {
    param([string]$Requested)
    if ($Requested) { return (Resolve-Path -LiteralPath $Requested).Path }
    foreach ($name in 'mihomo','mihomo.exe','verge-mihomo.exe') {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    if ($env:OS -eq 'Windows_NT') {
        foreach ($candidate in @((Join-Path $env:ProgramFiles 'Clash Verge\verge-mihomo.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Clash Verge\verge-mihomo.exe'))) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return [IO.Path]::GetFullPath($candidate) }
        }
    }
    return $null
}

function Render-Mihomo {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$ClientTarget, [Parameter(Mandatory)][string]$PrivateDirectory, [Parameter(Mandatory)][string]$OutputPath)
    $payloads = Get-ProfileRoutePayloads -Inventory $Inventory -Profile $Profile -PrivateDirectory $PrivateDirectory
    $parsed = Read-RouteNodes -PayloadPaths $payloads
    $providers = @(Get-ProfileProviders -Inventory $Inventory -Profile $Profile -PrivateDirectory $PrivateDirectory)
    $policy = [string](Get-RSTOptional $Profile 'policy' 'privacy')
    if ([string]::IsNullOrWhiteSpace($policy)) { $policy = 'privacy' }
    $nodeLines = @($parsed.Nodes | ForEach-Object { '      - ' + (ConvertTo-YamlSingleQuoted $_.Name) })
    $providerYaml = ''
    $providerUse = ''
    if ($providers.Count) {
        $blocks = @($providers | ForEach-Object {
@"
  $($_.Id):
    type: http
    url: $(ConvertTo-YamlSingleQuoted $_.Url)
    path: ./proxy_providers/$($_.Id).yaml
    interval: $($_.Interval)
    proxy: DIRECT
    health-check:
      enable: false
"@
        })
        $providerYaml = "proxy-providers:`n" + ($blocks -join '') + "`n"
        $providerUse = "    use:`n" + (@($providers | ForEach-Object { '      - ' + (ConvertTo-YamlSingleQuoted $_.Id) }) -join "`n") + "`n"
    }
    $dns = Get-DnsYaml -Policy $policy
    $policyRules = Get-PolicyRulesYaml -Policy $policy
    $text = @"
# route-steward: agent-native
# Private file: contains live proxy credentials.
mode: rule
ipv6: true
profile:
  store-selected: true
  store-fake-ip: true
tun:
  enable: true
  stack: mixed
  auto-route: true
  strict-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

$dns
proxies:
$($parsed.Bodies -join "`n")

$providerYaml
proxy-groups:
  - name: Private Routes
    type: select
    proxies:
$($nodeLines -join "`n")
$providerUse
rules:
  - DOMAIN,localhost,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve
$policyRules  - MATCH,Private Routes
"@
    [IO.File]::WriteAllText($OutputPath, $text, [Text.UTF8Encoding]::new($false))
    Protect-RSTPath -Path $OutputPath
    $validation = 'skipped'
    if (-not $SkipValidation) {
        $core = Resolve-MihomoCore -Requested $MihomoPath
        if ($core) {
            $validationHome = Join-Path ([IO.Path]::GetTempPath()) ('rst-mihomo-' + [Guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $validationHome | Out-Null
                $null = & $core -t -d $validationHome -f $OutputPath 2>&1
                if ($LASTEXITCODE -ne 0) { throw 'Mihomo rejected the generated ClientTarget.' }
                $validation = 'passed'
            }
            finally { if (Test-Path -LiteralPath $validationHome) { Remove-Item -LiteralPath $validationHome -Recurse -Force } }
        }
        else { $validation = 'unavailable' }
    }
    return [ordered]@{ client_target = [string]$ClientTarget.id; profile = [string]$Profile.id; renderer = 'mihomo'; path = [IO.Path]::GetFullPath($OutputPath); node_count = $parsed.Nodes.Count; provider_count = $providers.Count; validation = $validation }
}

function Render-Hysteria2 {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$ClientTarget, [Parameter(Mandatory)][string]$PrivateDirectory, [Parameter(Mandatory)][string]$OutputPath)
    $routeId = [string](Get-RSTOptional $ClientTarget 'route')
    $routes = @($Inventory.routes | Where-Object id -eq $routeId)
    if ($routes.Count -ne 1 -or (Get-RSTOptional $routes[0] 'enabled' $true) -eq $false) { throw "Hysteria2 ClientTarget '$($ClientTarget.id)' does not select an enabled Route." }
    $included = @(Get-RSTOptional $Profile 'include_routes' @('*'))
    if ($included -notcontains '*' -and $included -notcontains $routeId) { throw "Hysteria2 ClientTarget '$($ClientTarget.id)' selects a Route outside its Profile." }
    $listen = [string](Get-RSTOptional $ClientTarget 'listen')
    if (-not (Test-RSTLoopbackListener $listen)) { throw "Hysteria2 ClientTarget '$($ClientTarget.id)' must use a loopback listener." }
    $payload = Resolve-RSTSecret -Reference ([string]$routes[0].payload_secret_ref) -PrivateDirectory $PrivateDirectory
    $parsed = Read-RouteNodes -PayloadPaths @($payload)
    $family = [string](Get-RSTOptional $ClientTarget 'ingress_family' 'auto')
    $candidates = @($parsed.Nodes | ForEach-Object {
        $server = Get-NodeValue -Body $_.Body -Key 'server' -Required
        $address = $null
        if (-not [Net.IPAddress]::TryParse($server, [ref]$address)) { throw "Node '$($_.Name)' does not use a literal ingress address." }
        [pscustomobject]@{ Node = $_; Server = $server; Family = if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { 'ipv6' } else { 'ipv4' } }
    })
    $selected = $null
    if ($family -eq 'auto') {
        $selected = @($candidates | Where-Object Family -eq 'ipv4' | Select-Object -First 1)
        if (-not $selected.Count) { $selected = @($candidates | Where-Object Family -eq 'ipv6' | Select-Object -First 1) }
    }
    elseif ($family -in @('ipv4','ipv6')) { $selected = @($candidates | Where-Object Family -eq $family | Select-Object -First 1) }
    else { throw "Hysteria2 ClientTarget '$($ClientTarget.id)' has an unsupported ingress family." }
    if (-not $selected.Count) { throw "Hysteria2 ClientTarget '$($ClientTarget.id)' has no '$family' ingress." }
    $node = $selected[0].Node
    $port = Get-NodeValue -Body $node.Body -Key 'port' -Required
    $portNumber = 0
    if (-not [int]::TryParse($port, [ref]$portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535) { throw "Node '$($node.Name)' has an invalid port." }
    $auth = Get-NodeValue -Body $node.Body -Key 'password' -Required
    $sni = Get-NodeValue -Body $node.Body -Key 'sni' -Required
    $fingerprint = ConvertTo-NormalizedFingerprint -Value (Get-NodeValue -Body $node.Body -Key 'fingerprint' -Required) -NodeName $node.Name
    $obfs = Get-NodeValue -Body $node.Body -Key 'obfs' -Required
    if ($obfs -ne 'salamander') { throw "Node '$($node.Name)' uses unsupported Hysteria2 obfuscation." }
    $config = [ordered]@{
        server = ('{0}:{1}' -f (Format-UriHost $selected[0].Server), $portNumber)
        auth = $auth
        tls = [ordered]@{ sni = $sni; insecure = $true; pinSHA256 = $fingerprint }
        obfs = [ordered]@{ type = 'salamander'; salamander = [ordered]@{ password = (Get-NodeValue -Body $node.Body -Key 'obfs-password' -Required) } }
        http = [ordered]@{ listen = $listen }
        socks5 = [ordered]@{ listen = $listen }
    }
    [IO.File]::WriteAllText($OutputPath, ($config | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Protect-RSTPath -Path $OutputPath
    return [ordered]@{ client_target = [string]$ClientTarget.id; profile = [string]$Profile.id; renderer = 'hysteria2'; path = [IO.Path]::GetFullPath($OutputPath); node_count = 1; validation = 'official-json-structure-checked' }
}

function Get-SubscriptionUrl {
    param([Parameter(Mandatory)]$ClientTarget, [Parameter(Mandatory)][string]$PrivateDirectory)
    $reference = [string](Get-RSTOptional $ClientTarget 'subscription_secret_ref')
    if (-not $reference) { return $null }
    $path = Resolve-RSTSecret -Reference $reference -PrivateDirectory $PrivateDirectory
    $doc = Read-RSTJson -Path $path -Label 'The private subscription secret'
    $hostName = [string](Get-RSTOptional $doc 'host')
    $token = [string](Get-RSTOptional $doc 'token')
    if (-not $hostName -or $token -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'The private subscription secret is invalid.' }
    return 'https://{0}/s/{1}' -f $hostName, $token
}

function Render-Shadowrocket {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)]$Profile, [Parameter(Mandatory)]$ClientTarget, [Parameter(Mandatory)][string]$PrivateDirectory, [Parameter(Mandatory)][string]$OutputPath)
    $payloads = Get-ProfileRoutePayloads -Inventory $Inventory -Profile $Profile -PrivateDirectory $PrivateDirectory
    $parsed = Read-RouteNodes -PayloadPaths $payloads
    $nodes = @($parsed.Nodes | ForEach-Object { [ordered]@{ name = $_.Name; uri = ConvertTo-ShadowrocketUri $_ } })
    $subscriptionUrl = Get-SubscriptionUrl -ClientTarget $ClientTarget -PrivateDirectory $PrivateDirectory
    $payloadsForQr = if ($subscriptionUrl) {
        @([ordered]@{ name = 'Private subscription'; uri = ('sub://' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($subscriptionUrl)).TrimEnd('=').Replace('+','-').Replace('/','_')) })
    }
    else { $nodes }
    $data = @($payloadsForQr | ForEach-Object { [ordered]@{ name = $_.name; encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$_.uri)) } }) | ConvertTo-Json -Compress
    $vendorPath = Join-Path $PSScriptRoot 'vendor\qrcode-generator-1.4.4.js'
    $vendor = [IO.File]::ReadAllText($vendorPath, [Text.Encoding]::UTF8).Replace('</script','<\/script')
    $app = @"
;(() => {
  'use strict';
  const items = $data;
  const decode = (v) => new TextDecoder().decode(Uint8Array.from(atob(v), c => c.charCodeAt(0)));
  const root = document.getElementById('items');
  for (const item of items) {
    const card = document.createElement('section');
    const title = document.createElement('h2'); title.textContent = item.name;
    const box = document.createElement('div'); box.className = 'qr';
    const qr = qrcode(0, 'L'); qr.addData(decode(item.encoded), 'Byte'); qr.make(); box.innerHTML = qr.createSvgTag({ scalable: true, margin: 4 });
    card.append(title, box); root.append(card);
  }
})();
"@
    $script = $vendor + "`n" + $app
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [Convert]::ToBase64String($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($script))) } finally { $sha.Dispose() }
    $html = @"
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'sha256-$hash'; base-uri 'none'; connect-src 'none'"><title>Route Steward · Shadowrocket</title><style>body{font-family:system-ui,sans-serif;max-width:720px;margin:0 auto;padding:24px}h1{font-size:1.35rem}#items{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px}section{border:1px solid #ccc;border-radius:14px;padding:14px;text-align:center}.qr{width:min(220px,100%);margin:auto;background:#fff}.qr svg{width:100%;height:auto}h2{font-size:.9rem;overflow-wrap:anywhere}p{color:#666;font-size:.85rem}</style></head><body><h1>Shadowrocket import</h1><p>Offline private import page. Keep this file private.</p><main id="items"></main><script>$script</script></body></html>
"@
    if ($html -match '(?i)(?:src|href)\s*=\s*["'']https?://' -or $html -match '(?i)\bfetch\s*\(') { throw 'Shadowrocket output contains an external request.' }
    [IO.File]::WriteAllText($OutputPath, $html, [Text.UTF8Encoding]::new($false))
    Protect-RSTPath -Path $OutputPath
    return [ordered]@{ client_target = [string]$ClientTarget.id; profile = [string]$Profile.id; renderer = 'shadowrocket'; path = [IO.Path]::GetFullPath($OutputPath); node_count = $parsed.Nodes.Count; subscription = [bool]$subscriptionUrl; validation = 'offline-structure-checked' }
}

$InventoryPath = [IO.Path]::GetFullPath($InventoryPath)
$privateDirectory = Split-Path -Parent $InventoryPath
$inventory = Read-RSTInventory -Path $InventoryPath
if (-not $OutputDirectory) { $OutputDirectory = [string]$inventory.delivery.directory }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Protect-RSTPath -Path $OutputDirectory -Directory
$targets = @(Get-RSTClientTargets -Inventory $inventory)
if ($ClientTargetId) { $targets = @($targets | Where-Object id -eq $ClientTargetId) }
if (-not $targets.Count) { throw "Unknown ClientTarget '$ClientTargetId'." }
$results = [Collections.Generic.List[object]]::new()
foreach ($target in $targets) {
    $profile = Get-RSTProfileForClientTarget -Inventory $inventory -ClientTarget $target
    switch ([string]$target.renderer) {
        'mihomo' { $results.Add((Render-Mihomo -Inventory $inventory -Profile $profile -ClientTarget $target -PrivateDirectory $privateDirectory -OutputPath (Join-Path $OutputDirectory ($target.id + '.yaml')))) }
        'shadowrocket' { $results.Add((Render-Shadowrocket -Inventory $inventory -Profile $profile -ClientTarget $target -PrivateDirectory $privateDirectory -OutputPath (Join-Path $OutputDirectory ($target.id + '.html')))) }
        'hysteria2' { $results.Add((Render-Hysteria2 -Inventory $inventory -Profile $profile -ClientTarget $target -PrivateDirectory $privateDirectory -OutputPath (Join-Path $OutputDirectory ($target.id + '.json')))) }
        default { throw "ClientTarget '$($target.id)' uses unsupported renderer '$($target.renderer)'." }
    }
}
[ordered]@{ schema_version = 1; command = 'render-client-targets'; success = $true; outputs = @($results) } | ConvertTo-Json -Depth 10 -Compress
