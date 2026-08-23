[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,62}$')][string]$LinkId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repo 'lib\RouteSteward.Core.ps1')

function New-WireGuardKeyPair {
    $curve = [Security.Cryptography.ECCurve]::CreateFromFriendlyName('curve25519')
    $key = [Security.Cryptography.ECDiffieHellman]::Create($curve)
    try {
        $parameters = $key.ExportParameters($true)
        if ($parameters.D.Length -ne 32 -or $parameters.Q.X.Length -ne 32) { throw 'The platform returned an unexpected X25519 key size.' }
        return [ordered]@{
            private_key = [Convert]::ToBase64String($parameters.D)
            public_key = [Convert]::ToBase64String($parameters.Q.X)
        }
    }
    finally { $key.Dispose() }
}

$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw "Managed Link secret for '$LinkId' already exists." }
$secret = [ordered]@{
    schema = 1
    link_id = $LinkId
    created_at = [DateTime]::UtcNow.ToString('o')
    entry = New-WireGuardKeyPair
    exit = New-WireGuardKeyPair
}
Write-RSTJsonAtomic -Value $secret -Path $OutputPath
