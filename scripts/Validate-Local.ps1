[CmdletBinding()]
param(
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skipped = [Collections.Generic.List[string]]::new()

function Invoke-ValidationStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    Write-Host "==> $Name"
    & $Action
}

function Test-CommandAvailable([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

Push-Location $repo
try {
    $go = Get-Command go -ErrorAction SilentlyContinue
    if (-not $go) {
        $portableGo = Join-Path $repo '.tools\go\bin\go.exe'
        if (Test-Path -LiteralPath $portableGo -PathType Leaf) { $go = [pscustomobject]@{ Source = $portableGo } }
    }
    if (-not $go) { throw 'Go 1.27 is required to validate a source-development checkout. Normal users should use a verified Route Steward Release binary; this validation script does not install Go.' }
    $goVersion = (& $go.Source env GOVERSION 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $goVersion -notmatch '^go1\.27(?:\.|$)') { throw "Go 1.27 is required to validate a source-development checkout; found '$goVersion'." }
    $gofmtName = 'gofmt'
    if ($env:OS -eq 'Windows_NT') { $gofmtName = 'gofmt.exe' }
    $gofmt = Join-Path (Split-Path -Parent $go.Source) $gofmtName
    Invoke-ValidationStep 'Native Go formatting' {
        $goFiles = @(Get-ChildItem -Path $repo -Recurse -Filter '*.go' -File | Where-Object { $_.FullName -notmatch '[\\/](?:\.tools|bin)[\\/]' } | ForEach-Object FullName)
        $unformatted = @(& $gofmt -l @goFiles)
        if ($LASTEXITCODE -ne 0 -or $unformatted.Count) { throw ('Go formatting failed: ' + ($unformatted -join ', ')) }
    }
    Invoke-ValidationStep 'Native Go module, tests and vet' {
        & $go.Source mod verify
        if ($LASTEXITCODE -ne 0) { throw 'go mod verify failed.' }
        & $go.Source test ./... -timeout 180s
        if ($LASTEXITCODE -ne 0) { throw 'go test failed.' }
        & $go.Source vet ./...
        if ($LASTEXITCODE -ne 0) { throw 'go vet failed.' }
    }
    Invoke-ValidationStep 'Native executable' {
        $binaryName = 'bin/route-steward'
        if ($env:OS -eq 'Windows_NT') { $binaryName = 'bin\route-steward.exe' }
        $binary = Join-Path $repo $binaryName
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $binary) | Out-Null
        & $go.Source build -trimpath -o $binary ./cmd/route-steward
        if ($LASTEXITCODE -ne 0) { throw 'Route Steward executable build failed.' }
    }
    Invoke-ValidationStep 'Secret/generated-file scan' { & ./scripts/Check-NoSecrets.ps1 }
    Invoke-ValidationStep 'Architecture/public-tree contract' { & ./scripts/Test-Templates.ps1 }
    Invoke-ValidationStep 'Product version' { & ./tests/Test-Version.ps1 }
    Invoke-ValidationStep 'Agent/context/authorization' { & ./tests/Test-Agent.ps1 }

    if (-not $Quick) {
        if (Test-CommandAvailable 'npm') {
            Invoke-ValidationStep 'Worker locked install, test and dry-run' {
                Push-Location (Join-Path $repo 'worker')
                try {
                    & npm ci --no-audit --no-fund
                    if ($LASTEXITCODE -ne 0) { throw 'Worker npm ci failed.' }
                    & npm run types
                    if ($LASTEXITCODE -ne 0) { throw 'Worker type generation failed.' }
                    & npm run typecheck
                    if ($LASTEXITCODE -ne 0) { throw 'Worker typecheck failed.' }
                    & npm test
                    if ($LASTEXITCODE -ne 0) { throw 'Worker tests failed.' }
                    & npm run deploy:dry-run
                    if ($LASTEXITCODE -ne 0) { throw 'Worker Wrangler dry-run failed.' }
                    & npm audit --audit-level=low
                    if ($LASTEXITCODE -ne 0) { throw 'Worker dependency audit failed.' }
                }
                finally { Pop-Location }
            }
        }
        else { $skipped.Add('Optional Worker validation: npm is not installed.') }

        if (Test-CommandAvailable 'bash') {
            Invoke-ValidationStep 'Server Bash syntax' {
                $scripts = @(Get-ChildItem -LiteralPath (Join-Path $repo 'server') -Filter '*.sh' -File)
                foreach ($script in $scripts) {
                    $relative = [IO.Path]::GetRelativePath($repo, $script.FullName).Replace('\','/')
                    & bash -n $relative
                    if ($LASTEXITCODE -ne 0) { throw "Bash syntax failed: $($script.Name)" }
                }
            }
        }
        else { $skipped.Add('Server Bash syntax: bash is not installed.') }

        if (Test-CommandAvailable 'shellcheck') {
            Invoke-ValidationStep 'Server ShellCheck' {
                $scripts = @(Get-ChildItem -LiteralPath (Join-Path $repo 'server') -Filter '*.sh' -File | ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName).Replace('\','/') })
                & shellcheck @scripts
                if ($LASTEXITCODE -ne 0) { throw 'ShellCheck failed.' }
            }
        }
        else { $skipped.Add('Server ShellCheck: shellcheck is not installed.') }
    }

    if ($skipped.Count) {
        Write-Warning ('Skipped environment-dependent validation:' + [Environment]::NewLine + (($skipped | ForEach-Object { "- $_" }) -join [Environment]::NewLine))
    }
    if ($Quick) { Write-Host 'Local quick validation passed.' }
    else { Write-Host 'Local validation passed for all available toolchains.' }
}
finally {
    Pop-Location
}
