[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')
. (Join-Path $repo 'lib\RouteSteward.Model.ps1')
$agent = Join-Path $repo 'agent\route-steward-agent.ps1'
$stage = Join-Path ([IO.Path]::GetTempPath()) ('rst-provider-test-' + [Guid]::NewGuid().ToString('N'))
try {
    $null = & $agent bootstrap -PrivateDirectory $stage | ConvertFrom-Json
    $providerUrl = 'https://provider.example.invalid/subscription/private-fixture'
    $addContext = [ordered]@{ provider_id = 'travel-provider'; display_name = 'Travel Provider'; url = $providerUrl; interval_seconds = 86400 } | ConvertTo-Json -Compress

    $preflight = & $agent preflight -PrivateDirectory $stage -Operation add-provider -ContextJson $addContext | ConvertFrom-Json
    Assert-True $preflight.data.ready 'Complete add-provider context did not pass preflight.'
    $added = & $agent execute -PrivateDirectory $stage -Operation add-provider -ContextJson $addContext | ConvertFrom-Json
    Assert-True ($added.success -and $added.data.result.id -eq 'travel-provider') 'Generic Provider add failed.'
    Assert-True $added.data.result.url_stored_as_secret 'Provider URL was not treated as secret state.'

    $inventoryPath = Join-Path $stage 'inventory.json'
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True (@($inventory.providers).Count -eq 1) 'Provider was not persisted in desired state.'
    Assert-True ([string]$inventory.providers[0].source_type -eq 'mihomo-http' -and -not $inventory.providers[0].PSObject.Properties['url_secret_ref']) 'Provider did not use the canonical source contract.'
    $secretPath = Resolve-RSTSecret -Reference ([string]$inventory.providers[0].source_secret_ref) -PrivateDirectory $stage
    Assert-True ([IO.File]::ReadAllText($secretPath, [Text.Encoding]::UTF8).Trim() -eq $providerUrl) 'Provider URL secret does not match the requested URL.'

    $context = & $agent context -PrivateDirectory $stage | ConvertFrom-Json
    $contextText = $context | ConvertTo-Json -Depth 20
    Assert-True (-not $contextText.Contains($providerUrl)) 'Sanitized agent context leaked a Provider URL.'

    $updateContext = [ordered]@{ display_name = 'Updated Provider'; enabled = $false } | ConvertTo-Json -Compress
    $updated = & $agent execute -PrivateDirectory $stage -Operation update-provider -Target travel-provider -ContextJson $updateContext | ConvertFrom-Json
    Assert-True ($updated.success -and -not $updated.data.result.enabled) 'Provider update failed.'

    $invalidUrl = 'https://changed.example.invalid/should-not-stick'
    $invalidContext = [ordered]@{ url = $invalidUrl; interval_seconds = 30 } | ConvertTo-Json -Compress
    $failedUpdate = & $agent execute -PrivateDirectory $stage -Operation update-provider -Target travel-provider -ContextJson $invalidContext | ConvertFrom-Json
    Assert-True (-not $failedUpdate.success) 'Invalid Provider update unexpectedly succeeded.'
    Assert-True ([IO.File]::ReadAllText($secretPath, [Text.Encoding]::UTF8).Trim() -eq $providerUrl) 'Failed Provider update changed the canonical URL secret.'
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True ([int]$inventory.providers[0].interval_seconds -eq 86400) 'Failed Provider update changed desired state.'

    $profileContext = [ordered]@{ profile_id = 'provider-user'; include_routes = @('*'); include_providers = @('travel-provider') } | ConvertTo-Json -Compress
    $createdProfile = & $agent execute -PrivateDirectory $stage -Operation add-profile -ContextJson $profileContext | ConvertFrom-Json
    Assert-True $createdProfile.success 'Explicit Provider-using Profile creation failed.'
    $blocked = & $agent preflight -PrivateDirectory $stage -Operation remove-provider -Target travel-provider | ConvertFrom-Json
    Assert-True (-not $blocked.data.ready -and @($blocked.data.conflicts) -contains 'provider-still-referenced-by-profile') 'Referenced Provider removal was not blocked.'

    $inventory = Read-RSTInventory -Path $inventoryPath
    (@($inventory.profiles | Where-Object id -eq 'provider-user')[0]).include_providers = @()
    Save-RSTInventory -Inventory $inventory -InventoryPath $inventoryPath
    $removed = & $agent execute -PrivateDirectory $stage -Operation remove-provider -Target travel-provider | ConvertFrom-Json
    Assert-True ($removed.success -and $removed.data.result.removed) 'Unreferenced Provider removal failed.'
    $inventory = Read-RSTInventory -Path $inventoryPath
    Assert-True (@($inventory.providers).Count -eq 0) 'Removed Provider remains in desired state.'
    Assert-True (-not (Test-Path -LiteralPath $secretPath)) 'Removed Provider URL secret remains on disk.'

    Write-Host 'Canonical Provider lifecycle, rollback, dependency blocking, secret storage, and agent redaction tests passed.'
}
finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
