[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\PrivateProxyManager.Core.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Model.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Provider.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Agent.ps1')
. (Join-Path $repo 'lib\PrivateProxyManager.Recovery.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('ppm-recovery-core-test-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'extracted'
$target = Join-Path $root 'restored-private'
$tampered = Join-Path $root 'tampered'
$tamperedTarget = Join-Path $root 'tampered-target'
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $source 'private\secrets'), (Join-Path $source 'ssh\entry-a') | Out-Null
    $inventory = New-PPMCleanInventory -PrivateDirectory (Join-Path $source 'private')
    $inventory.servers = @([pscustomobject][ordered]@{
        id = 'entry-a'; provider = 'byo'; account_label = 'personal'; instance_name = 'entry-a'; region = 'example-region'; zone = ''; os = 'ubuntu-24.04'; architecture = 'x86_64'; compute = [pscustomobject][ordered]@{ driver = 'byo-ssh'; host_ownership = 'dedicated' }; roles = @('entry','exit')
        network = [pscustomobject][ordered]@{ public_ipv4 = '192.0.2.50'; ipv4_type = 'static'; private_ipv4 = $null; public_ipv6 = '2001:db8::50'; expected_egress_ipv4 = '192.0.2.50'; expected_egress_ipv6 = $null }
        ssh = [pscustomobject][ordered]@{ user = 'ubuntu'; key_path = '/old/location/id_ed25519'; allowed_sources = @('trusted') }
        firewall = [pscustomobject][ordered]@{ profile = 'pending'; rules = @([pscustomobject][ordered]@{ family = 'dual'; protocol = 'tcp'; port = 22; source = 'trusted' }) }
    })
    [IO.File]::WriteAllText((Join-Path $source 'private\inventory.json'), ($inventory | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'private\secrets\index.json'), (([ordered]@{ schema = 1; refs = [ordered]@{} }) | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'private\operator.json'), ((New-PPMDefaultOperatorContext) | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'private\observed.json'), '{"schema":1,"generated_at":"2026-01-01T00:00:00Z","servers":[],"links":[],"routes":[{"route":"stale"}]}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $source 'ssh\entry-a\id_ed25519'), 'fixture-private-key', [Text.UTF8Encoding]::new($false))
    $metadata = [ordered]@{ schema = 1; product = 'private-proxy-manager'; inventory_schema = 1; recovery_model = 'agent-native-local-state' }
    [IO.File]::WriteAllText((Join-Path $source 'RECOVERY-METADATA.json'), ($metadata | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

    $manifest = Get-ChildItem -LiteralPath $source -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($source.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    [IO.File]::WriteAllLines((Join-Path $source 'SHA256SUMS'), $manifest, [Text.UTF8Encoding]::new($false))

    $result = Restore-PPMExtractedRecovery -ExtractedDirectory $source -PrivateDirectory $target
    Assert-True $result.restored 'Recovery core did not report success.'
    Assert-True (-not $result.remote_changed) 'Recovery core must remain local-only.'
    Assert-True $result.observed_state_reset 'Recovery core did not reset observed evidence.'
    Assert-True ($result.inventory_schema -eq 1) 'Recovery core did not restore public inventory schema 1.'
    Assert-True ($result.servers -eq 1 -and $result.routes -eq 0) 'Recovered inventory counts are wrong.'

    $restored = Read-PPMInventory -Path (Join-Path $target 'inventory.json')
    Assert-True ($restored.schema -eq 1) 'Recovered inventory does not pass schema-1 validation.'
    Assert-True (@($restored.client_targets).Count -eq 0 -and @($restored.profiles).Count -eq 0) 'Recovery introduced client or policy assumptions.'
    $restoredKey = [string]$restored.servers[0].ssh.key_path
    Assert-True ($restoredKey.StartsWith([IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase)) 'Recovered SSH key path still points outside the restored private directory.'
    Assert-True (Test-Path -LiteralPath $restoredKey -PathType Leaf) 'Recovered SSH key is missing.'
    Assert-True (Test-PPMPrivateAcl -Path $restoredKey) 'Recovered SSH key permissions are not owner-only.'
    Assert-True ([IO.Path]::GetFullPath([string]$restored.delivery.directory) -eq [IO.Path]::GetFullPath((Join-Path $target 'delivery'))) 'Delivery directory was not rebound to restored private state.'
    $observed = Read-PPMJson -Path (Join-Path $target 'observed.json') -Label 'Restored observed state'
    Assert-True ($null -eq $observed.generated_at -and @($observed.routes).Count -eq 0) 'Stale observed evidence survived recovery.'

    Copy-Item -LiteralPath $source -Destination $tampered -Recurse
    [IO.File]::AppendAllText((Join-Path $tampered 'private\inventory.json'), "`n ", [Text.UTF8Encoding]::new($false))
    $failed = $false
    try { $null = Restore-PPMExtractedRecovery -ExtractedDirectory $tampered -PrivateDirectory $tamperedTarget }
    catch { $failed = $_.Exception.Message -match 'manifest|SHA-256' }
    Assert-True $failed 'Tampered recovery content was not rejected by manifest verification.'
    Assert-True (-not (Test-Path -LiteralPath $tamperedTarget)) 'Failed recovery left a partial destination.'

    Write-Host 'Schema-1 recovery restore, path rebinding, permission hardening, observed reset, and tamper rejection tests passed.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
