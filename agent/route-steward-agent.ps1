[CmdletBinding()]
param(
    [Parameter(Position = 0)][ValidateSet('capabilities','bootstrap','context','drift','preflight','execute')][string]$Command = 'context',
    [string]$Operation,
    [string]$Target,
    [string]$ContextJson,
    [switch]$ContextStdin,
    [string]$PrivateDirectory,
    [switch]$Approved
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $PrivateDirectory) { $PrivateDirectory = Join-Path $repo 'private' }

$binaryName = if ($env:OS -eq 'Windows_NT') { 'route-steward.exe' } else { 'route-steward' }
$candidates = @()
if ($env:RST_ROUTE_STEWARD_BIN) { $candidates += $env:RST_ROUTE_STEWARD_BIN }
$candidates += Join-Path $repo (Join-Path 'bin' $binaryName)
$installed = Get-Command route-steward -ErrorAction SilentlyContinue
if ($installed) { $candidates += $installed.Source }
$binary = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1

$arguments = @($Command, '--private-dir', [IO.Path]::GetFullPath($PrivateDirectory))
if ($Operation) { $arguments += @('--operation', $Operation) }
if ($Target) { $arguments += @('--target', $Target) }
if ($ContextJson) { $arguments += @('--context-json', $ContextJson) }
if ($ContextStdin) { $arguments += '--context-stdin' }
if ($Approved) { $arguments += '--approved' }

if ($binary) {
    if ($ContextStdin) { [Console]::In.ReadToEnd() | & $binary @arguments }
    else { & $binary @arguments }
    exit $LASTEXITCODE
}

$go = Get-Command go -ErrorAction SilentlyContinue
if (-not $go) { throw 'Route Steward executable was not found. Normal URL-first use should download a Release archive, verify it against SHA256SUMS, and put route-steward on PATH or set RST_ROUTE_STEWARD_BIN. Source-development checkout fallback requires Go 1.27 already available; this script does not install Go.' }
$goVersion = (& $go.Source env GOVERSION 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $goVersion -notmatch '^go1\.27(?:\.|$)') { throw "Source-development checkout fallback requires Go 1.27 already available; found '$goVersion'. Normal users should use a verified Release binary." }
$goArguments = @('run', './cmd/route-steward') + $arguments
Push-Location $repo
try {
    if ($ContextStdin) { [Console]::In.ReadToEnd() | & $go.Source @goArguments }
    else { & $go.Source @goArguments }
    exit $LASTEXITCODE
}
finally { Pop-Location }
