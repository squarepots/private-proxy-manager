$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Shared deterministic helpers for the final ClientTarget-scoped subscription
# implementation in RouteSteward.SubscriptionTargets.ps1. Lifecycle and
# state ownership intentionally do not live in this helper layer.

function New-RSTSubscriptionToken {
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}

function Get-RSTSha256Hex {
    param([Parameter(Mandatory)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Assert-RSTWorkerIdentity {
    param([Parameter(Mandatory)][string]$WorkerName, [Parameter(Mandatory)][string]$HostName)
    if ($WorkerName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw 'worker_name must be a valid Cloudflare Worker name.' }
    $hostValue = $HostName.Trim().ToLowerInvariant()
    $uri = $null
    if (-not [Uri]::TryCreate(('https://' + $hostValue + '/'), [UriKind]::Absolute, [ref]$uri) -or $uri.Host -ne $hostValue -or $hostValue -notmatch '^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$') {
        throw 'host must be one valid HTTPS hostname without scheme or path.'
    }
    return $hostValue
}

function Test-RSTSubscriptionEndpoint {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$ExpectedBody)
    try { $response = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec 30 -Headers @{ 'User-Agent' = 'RouteSteward/1' } }
    catch { throw 'The private subscription endpoint could not be verified after publication.' }
    if ([int]$response.StatusCode -ne 200 -or [string]$response.Content -cne $ExpectedBody) { throw 'The private subscription endpoint did not return the exact locally generated body.' }
    if ([string]$response.Headers['Cache-Control'] -notmatch '(?i)no-store') { throw 'The private subscription endpoint is missing its no-store cache policy.' }
    return $true
}
