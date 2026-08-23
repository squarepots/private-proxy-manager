$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-PPMSubscriptionBodySize {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Body)
    $byteCount = [Text.Encoding]::UTF8.GetByteCount($Body)
    if ($byteCount -gt 5120) { throw 'subscription-payload-too-large' }
    return $byteCount
}

function Get-PPMShadowrocketClientTarget {
    param([Parameter(Mandatory)]$Inventory, [Parameter(Mandatory)][string]$TargetId)
    $target = Get-PPMClientTargetById -Inventory $Inventory -Id $TargetId
    if ([string]$target.renderer -ne 'shadowrocket') { throw "ClientTarget '$TargetId' is not a Shadowrocket target." }
    return $target
}

function Get-PPMClientSubscriptionState {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [Parameter(Mandatory)][string]$TargetId,
        [switch]$AllowMissing
    )
    $target = Get-PPMShadowrocketClientTarget -Inventory $Inventory -TargetId $TargetId
    $reference = [string](Get-PPMOptional $target 'subscription_secret_ref')
    if (-not $reference) {
        if ($AllowMissing) { return $null }
        throw "ClientTarget '$TargetId' has no private subscription state."
    }
    $path = Resolve-PPMSecret -Reference $reference -PrivateDirectory $PrivateDirectory
    $doc = Read-PPMJson -Path $path -Label 'Private subscription state'
    $workerName = [string](Get-PPMOptional $doc 'worker_name')
    $hostName = [string](Get-PPMOptional $doc 'host')
    $token = [string](Get-PPMOptional $doc 'token')
    $pendingToken = [string](Get-PPMOptional $doc 'pending_token')
    $null = Assert-PPMWorkerIdentity -WorkerName $workerName -HostName $hostName
    if ([int](Get-PPMOptional $doc 'schema' 0) -ne 1 -or $token -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'Private subscription state is invalid.' }
    if ($pendingToken -and $pendingToken -notmatch '^[A-Za-z0-9_-]{43}$') { throw 'Private subscription pending token is invalid.' }
    return [pscustomobject][ordered]@{
        Reference = $reference
        Path = $path
        TargetId = $TargetId
        WorkerName = $workerName
        Host = $hostName
        Token = $token
        Url = ('https://{0}/s/{1}' -f $hostName, $token)
        PendingToken = if ($pendingToken) { $pendingToken } else { $null }
        LastPublishedAt = Get-PPMOptional $doc 'last_published_at'
    }
}

function Assert-PPMClientSubscriptionIdentityUnique {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$PrivateDirectory,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)][string]$WorkerName,
        [Parameter(Mandatory)][string]$HostName
    )
    foreach ($other in @(Get-PPMClientTargets -Inventory $Inventory)) {
        if ([string]$other.id -eq $TargetId) { continue }
        $reference = [string](Get-PPMOptional $other 'subscription_secret_ref')
        if (-not $reference) { continue }
        try { $state = Get-PPMClientSubscriptionState -Inventory $Inventory -PrivateDirectory $PrivateDirectory -TargetId ([string]$other.id) }
        catch { throw "ClientTarget '$($other.id)' has invalid subscription state; resolve it before allocating another subscription identity." }
        if ($state.WorkerName -eq $WorkerName) { throw "Worker '$WorkerName' is already assigned to ClientTarget '$($other.id)'. Each subscription target requires an isolated Worker identity." }
        if ($state.Host -eq $HostName) { throw "Subscription host '$HostName' is already assigned to ClientTarget '$($other.id)'. Each subscription target requires an isolated delivery endpoint." }
    }
    return $true
}

function Initialize-PPMClientSubscriptionState {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)][string]$WorkerName,
        [Parameter(Mandatory)][string]$HostName
    )
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $target = Get-PPMShadowrocketClientTarget -Inventory $Inventory -TargetId $TargetId
    $hostValue = Assert-PPMWorkerIdentity -WorkerName $WorkerName -HostName $HostName
    $null = Assert-PPMClientSubscriptionIdentityUnique -Inventory $Inventory -PrivateDirectory $privateDirectory -TargetId $TargetId -WorkerName $WorkerName -HostName $hostValue
    $existing = Get-PPMClientSubscriptionState -Inventory $Inventory -PrivateDirectory $privateDirectory -TargetId $TargetId -AllowMissing
    if ($existing) {
        if ($existing.WorkerName -ne $WorkerName -or $existing.Host -ne $hostValue) { throw 'Subscription delivery is already initialized for a different Worker or host; explicit reconfiguration is required.' }
        return $existing
    }

    $reference = 'subscription:' + (ConvertTo-PPMId $TargetId)
    $relative = 'subscriptions/' + (ConvertTo-PPMId $TargetId) + '.json'
    $secretPath = Join-Path $privateDirectory ('secrets\' + $relative.Replace('/','\'))
    $index = Read-PPMSecretIndex -PrivateDirectory $privateDirectory
    if ($index.refs.PSObject.Properties[$reference]) { throw "Secret reference '$reference' already exists." }
    $indexPath = Join-Path $privateDirectory 'secrets\index.json'
    $oldInventory = [IO.File]::ReadAllText($InventoryPath, [Text.Encoding]::UTF8)
    $oldIndex = [IO.File]::ReadAllText($indexPath, [Text.Encoding]::UTF8)
    $token = New-PPMSubscriptionToken
    $secret = [ordered]@{ schema = 1; worker_name = $WorkerName; host = $hostValue; token = $token; pending_token = $null; last_published_at = $null }
    try {
        Write-PPMJsonAtomic -Value $secret -Path $secretPath
        $index.refs | Add-Member -NotePropertyName $reference -NotePropertyValue ([pscustomobject][ordered]@{ type = 'cloudflare-subscription'; path = $relative })
        Write-PPMJsonAtomic -Value $index -Path $indexPath
        $target | Add-Member -NotePropertyName subscription_secret_ref -NotePropertyValue $reference -Force
        $target.delivery = 'subscription'
        Save-PPMInventory -Inventory $Inventory -InventoryPath $InventoryPath
    }
    catch {
        [IO.File]::WriteAllText($indexPath, $oldIndex, [Text.UTF8Encoding]::new($false)); Protect-PPMPath -Path $indexPath
        [IO.File]::WriteAllText($InventoryPath, $oldInventory, [Text.UTF8Encoding]::new($false)); Protect-PPMPath -Path $InventoryPath
        if (Test-Path -LiteralPath $secretPath) { Remove-Item -LiteralPath $secretPath -Force }
        throw
    }
    return Get-PPMClientSubscriptionState -Inventory (Read-PPMInventory -Path $InventoryPath) -PrivateDirectory $privateDirectory -TargetId $TargetId
}

function Invoke-PPMClientSubscriptionPublication {
    param(
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$TargetId,
        [Parameter(Mandatory)][string]$WorkerName,
        [Parameter(Mandatory)][string]$Host,
        [Parameter(Mandatory)][string]$Token
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $workerDirectory = Join-Path $repoRoot 'worker'
    if (-not (Test-Path -LiteralPath (Join-Path $workerDirectory 'node_modules\wrangler\bin\wrangler.js') -PathType Leaf)) { throw 'Worker dependencies are missing.' }
    $npx = if ($env:OS -eq 'Windows_NT') { 'npx.cmd' } else { 'npx' }
    if (-not (Get-Command $npx -ErrorAction SilentlyContinue)) { throw 'npx is unavailable.' }
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('ppm-subscription-' + [Guid]::NewGuid().ToString('N'))
    $oldMetrics = $env:WRANGLER_SEND_METRICS
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Protect-PPMPath -Path $stage -Directory
        $bodyPath = Join-Path $stage 'subscription.txt'
        $exportJson = & (Join-Path $repoRoot 'client\Export-ShadowrocketSubscription.ps1') -InventoryPath $InventoryPath -ClientTargetId $TargetId -OutputPath $bodyPath
        if ($LASTEXITCODE -ne 0) { throw 'Subscription body generation failed.' }
        $null = $exportJson | ConvertFrom-Json
        $body = [IO.File]::ReadAllText($bodyPath, [Text.Encoding]::UTF8)
        $null = Assert-PPMSubscriptionBodySize -Body $body
        $secretFile = Join-Path $stage 'worker-secrets.json'
        [IO.File]::WriteAllText($secretFile, ([ordered]@{ SUBSCRIPTION_TOKEN_HASH = Get-PPMSha256Hex -Value $Token; SUBSCRIPTION_BODY = $body } | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
        Protect-PPMPath -Path $secretFile
        $env:WRANGLER_SEND_METRICS = 'false'
        Push-Location $workerDirectory
        try {
            $dryOutput = @(& $npx wrangler deploy --config wrangler.jsonc --name $WorkerName --dry-run --strict 2>&1 | ForEach-Object { [string]$_ })
            if ($LASTEXITCODE -ne 0) { throw 'Worker strict dry-run failed; nothing was deployed.' }
            $deployOutput = @(& $npx wrangler deploy --config wrangler.jsonc --name $WorkerName --secrets-file $secretFile --keep-vars --minify --strict 2>&1 | ForEach-Object { [string]$_ })
            if ($LASTEXITCODE -ne 0) {
                if (($deployOutput -join ' ') -match '(?i)(login|auth|oauth|api token)') { throw 'Cloudflare authentication is required before subscription publication.' }
                throw 'Cloudflare rejected the Worker deployment.'
            }
        }
        finally { Pop-Location }
        $url = 'https://{0}/s/{1}' -f $Host, $Token
        Test-PPMSubscriptionEndpoint -Url $url -ExpectedBody $body
        return [ordered]@{ worker = $WorkerName; url_verified = $true; body = $body }
    }
    finally {
        $env:WRANGLER_SEND_METRICS = $oldMetrics
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}

function Publish-PPMClientSubscription {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$TargetId
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $state = Get-PPMClientSubscriptionState -Inventory $Inventory -PrivateDirectory $privateDirectory -TargetId $TargetId
    if ($state.PendingToken) { throw 'A subscription token rotation is pending. Complete or diagnose the rotation before ordinary publication.' }
    $published = Invoke-PPMClientSubscriptionPublication -InventoryPath $InventoryPath -TargetId $TargetId -WorkerName $state.WorkerName -Host $state.Host -Token $state.Token
    $secretDoc = Read-PPMJson -Path $state.Path -Label 'Private subscription state'
    $secretDoc | Add-Member -NotePropertyName last_published_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-PPMJsonAtomic -Value $secretDoc -Path $state.Path
    $renderJson = & (Join-Path $repoRoot 'client\Render-ClientTargets.ps1') -InventoryPath $InventoryPath -ClientTargetId $TargetId -SkipValidation
    if ($LASTEXITCODE -ne 0) { throw 'Subscription was published, but the local import artifact could not be rebuilt.' }
    $render = $renderJson | ConvertFrom-Json
    if (Get-Command Update-PPMClientRenderManifest -ErrorAction SilentlyContinue) {
        $freshInventory = Read-PPMInventory -Path $InventoryPath
        $null = Update-PPMClientRenderManifest -Inventory $freshInventory -InventoryPath $InventoryPath -PrivateDirectory $privateDirectory -Outputs @($render.outputs)
    }
    return [ordered]@{ client_target = $TargetId; worker = $state.WorkerName; published = $true; verified = [bool]$published.url_verified }
}

function Rotate-PPMClientSubscriptionToken {
    param(
        [Parameter(Mandatory)]$Inventory,
        [Parameter(Mandatory)][string]$InventoryPath,
        [Parameter(Mandatory)][string]$TargetId
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $privateDirectory = Split-Path -Parent ([IO.Path]::GetFullPath($InventoryPath))
    $state = Get-PPMClientSubscriptionState -Inventory $Inventory -PrivateDirectory $privateDirectory -TargetId $TargetId
    $doc = Read-PPMJson -Path $state.Path -Label 'Private subscription state'
    $proposed = if ($state.PendingToken) { [string]$state.PendingToken } else { New-PPMSubscriptionToken }
    if (-not $state.PendingToken) {
        $doc | Add-Member -NotePropertyName pending_token -NotePropertyValue $proposed -Force
        $doc | Add-Member -NotePropertyName rotation_started_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
        Write-PPMJsonAtomic -Value $doc -Path $state.Path
    }
    $published = Invoke-PPMClientSubscriptionPublication -InventoryPath $InventoryPath -TargetId $TargetId -WorkerName $state.WorkerName -Host $state.Host -Token $proposed
    $doc = Read-PPMJson -Path $state.Path -Label 'Private subscription state'
    if ([string](Get-PPMOptional $doc 'pending_token') -ne $proposed) { throw 'Subscription rotation intent changed during publication; refusing to promote the token.' }
    $doc.token = $proposed
    $doc.pending_token = $null
    $doc | Add-Member -NotePropertyName rotated_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $doc | Add-Member -NotePropertyName last_published_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    Write-PPMJsonAtomic -Value $doc -Path $state.Path
    $renderJson = & (Join-Path $repoRoot 'client\Render-ClientTargets.ps1') -InventoryPath $InventoryPath -ClientTargetId $TargetId -SkipValidation
    if ($LASTEXITCODE -ne 0) { throw 'Subscription token rotated and published, but the local import artifact could not be rebuilt.' }
    $render = $renderJson | ConvertFrom-Json
    if (Get-Command Update-PPMClientRenderManifest -ErrorAction SilentlyContinue) {
        $freshInventory = Read-PPMInventory -Path $InventoryPath
        $null = Update-PPMClientRenderManifest -Inventory $freshInventory -InventoryPath $InventoryPath -PrivateDirectory $privateDirectory -Outputs @($render.outputs)
    }
    return [ordered]@{
        client_target = $TargetId
        token_rotated = $true
        published = $true
        verified = [bool]$published.url_verified
        old_token_revoked_at_worker = $true
        unrelated_route_credentials_changed = $false
        unrelated_client_credentials_changed = $false
    }
}
