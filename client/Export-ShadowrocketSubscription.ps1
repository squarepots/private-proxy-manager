[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InventoryPath,
    [Parameter(Mandatory)][Alias('ProfileId')][string]$ClientTargetId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')

function ConvertFrom-RSTYamlScalar {
    param([Parameter(Mandatory)][string]$Value)
    $value = $Value.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") { return $value.Substring(1, $value.Length - 2).Replace("''", "'") }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') { return ($value | ConvertFrom-Json) }
    return $value
}

function Get-RSTNodeValue {
    param([Parameter(Mandatory)][string]$Body, [Parameter(Mandatory)][string]$Key)
    $match = [regex]::Match($Body, '(?m)^\s{4,10}' + [regex]::Escape($Key) + ':\s*(?<value>.*?)\s*$')
    if (-not $match.Success) { throw "A node is missing required field '$Key'." }
    return ConvertFrom-RSTYamlScalar $match.Groups['value'].Value
}

function ConvertTo-RSTUriComponent { param([Parameter(Mandatory)][AllowEmptyString()][string]$Value) return [Uri]::EscapeDataString($Value) }
function Format-RSTUriHost { param([Parameter(Mandatory)][string]$Address) if ($Address.Contains(':')) { return "[$Address]" }; return $Address }

function ConvertTo-RSTShadowrocketUri {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Body)
    $type = Get-RSTNodeValue -Body $Body -Key 'type'
    if ($type.ToLowerInvariant() -ne 'hysteria2') { throw "Node '$Name' uses unsupported type '$type'." }
    $server = Get-RSTNodeValue -Body $Body -Key 'server'
    $port = Get-RSTNodeValue -Body $Body -Key 'port'
    $auth = Get-RSTNodeValue -Body $Body -Key 'password'
    $sni = Get-RSTNodeValue -Body $Body -Key 'sni'
    $fingerprint = ((Get-RSTNodeValue -Body $Body -Key 'fingerprint') -replace '[:\s-]', '').ToLowerInvariant()
    if ($fingerprint -notmatch '^[0-9a-f]{64}$') { throw "Node '$Name' has an invalid SHA-256 certificate fingerprint." }
    $obfs = Get-RSTNodeValue -Body $Body -Key 'obfs'
    $obfsPassword = Get-RSTNodeValue -Body $Body -Key 'obfs-password'
    if ($obfs -ne 'salamander') { throw "Node '$Name' uses unsupported Hysteria2 obfuscation." }
    $query = @(
        'auth=' + (ConvertTo-RSTUriComponent $auth),
        'obfs=salamander',
        'obfs-password=' + (ConvertTo-RSTUriComponent $obfsPassword),
        'obfsParam=' + (ConvertTo-RSTUriComponent $obfsPassword),
        'sni=' + (ConvertTo-RSTUriComponent $sni),
        'peer=' + (ConvertTo-RSTUriComponent $sni),
        'alpn=h3','udp=1','insecure=1','pinSHA256=' + $fingerprint
    ) -join '&'
    return 'hysteria2://{0}@{1}:{2}/?{3}#{4}' -f (ConvertTo-RSTUriComponent $auth), (Format-RSTUriHost $server), $port, $query, (ConvertTo-RSTUriComponent $Name)
}

$InventoryPath = [IO.Path]::GetFullPath($InventoryPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$privateDirectory = Split-Path -Parent $InventoryPath
$inventory = Read-RSTInventory -Path $InventoryPath
$target = Get-RSTClientTargetById -Inventory $inventory -Id $ClientTargetId
if ([string]$target.renderer -ne 'shadowrocket') { throw "ClientTarget '$ClientTargetId' is not a Shadowrocket target." }
$profile = Get-RSTProfileForClientTarget -Inventory $inventory -ClientTarget $target
$include = @(Get-RSTOptional $profile 'include_routes' @('*'))
$routes = @($inventory.routes | Where-Object { (Get-RSTOptional $_ 'enabled' $true) -ne $false } | Sort-Object order)
if ($include -notcontains '*') { $routes = @($routes | Where-Object { $include -contains $_.id }) }
if (-not $routes.Count) { throw "Profile '$($profile.id)' has no enabled Routes for ClientTarget '$ClientTargetId'." }
$uris = [Collections.Generic.List[string]]::new()
foreach ($route in $routes) {
    $driver = [string](Get-RSTOptional (Get-RSTOptional $route 'ingress') 'driver' 'hysteria2')
    if ($driver -ne 'hysteria2') { throw "Route '$($route.id)' ingress driver '$driver' is unsupported by Shadowrocket export." }
    $payloadPath = Resolve-RSTSecret -Reference ([string]$route.payload_secret_ref) -PrivateDirectory $privateDirectory
    $raw = [IO.File]::ReadAllText($payloadPath, [Text.Encoding]::UTF8)
    if ($raw -notmatch '(?ms)^proxies:\s*\r?\n(?<nodes>.+)\z') { throw "Route '$($route.id)' client payload is invalid." }
    $blocks = [regex]::Matches($Matches.nodes, '(?ms)^\s{2}- name:\s*(?<name>[^\r\n]+)\r?\n(?<body>.*?)(?=^\s{2}- name:|\z)')
    foreach ($block in $blocks) {
        $name = ConvertFrom-RSTYamlScalar $block.Groups['name'].Value
        $uris.Add((ConvertTo-RSTShadowrocketUri -Name $name -Body $block.Groups['body'].Value))
    }
}
if (-not $uris.Count) { throw 'No Shadowrocket nodes were produced.' }
$plain = @($uris) -join "`n"
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($plain))
if ([Text.Encoding]::UTF8.GetByteCount($encoded) -gt 5000) { throw 'The encoded subscription exceeds the configured Worker secret payload limit.' }
$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
Protect-RSTPath -Path $directory -Directory
[IO.File]::WriteAllText($OutputPath, $encoded, [Text.UTF8Encoding]::new($false))
Protect-RSTPath -Path $OutputPath
[ordered]@{ schema_version = 1; client_target = $ClientTargetId; profile = [string]$profile.id; node_count = $uris.Count; output = $OutputPath } | ConvertTo-Json -Compress
