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
    Invoke-ValidationStep 'Secret/generated-file scan' { & ./scripts/Check-NoSecrets.ps1 }
    Invoke-ValidationStep 'Architecture/public-tree contract' { & ./scripts/Test-Templates.ps1 }
    Invoke-ValidationStep 'Product version' { & ./tests/Test-Version.ps1 }
    Invoke-ValidationStep 'Agent/context/authorization' { & ./tests/Test-Agent.ps1 }
    Invoke-ValidationStep 'Core state/model' { & ./tests/Test-Core.ps1 }
    Invoke-ValidationStep 'Provider lifecycle' { & ./tests/Test-Providers.ps1 }
    Invoke-ValidationStep 'ClientTarget rendering' { & ./tests/Test-ClientTargets.ps1 }
    Invoke-ValidationStep 'Observed state and drift' { & ./tests/Test-Observed.ps1 }
    Invoke-ValidationStep 'Subscription lifecycle' { & ./tests/Test-Subscription.ps1 }
    Invoke-ValidationStep 'Recovery core' { & ./tests/Test-RecoveryCore.ps1 }

    if (-not $Quick) {
        if ((Test-CommandAvailable '7z') -or (Test-CommandAvailable '7zz') -or (Test-CommandAvailable '7z.exe')) {
            Invoke-ValidationStep 'Encrypted recovery archive' { & ./tests/Test-Recovery.ps1 }
        }
        else { $skipped.Add('Encrypted recovery archive: 7-Zip is not installed.') }

        if (Test-CommandAvailable 'npm') {
            Invoke-ValidationStep 'MCP locked install and typecheck' {
                Push-Location (Join-Path $repo 'mcp')
                try {
                    & npm ci --ignore-scripts --no-audit --no-fund
                    if ($LASTEXITCODE -ne 0) { throw 'MCP npm ci failed.' }
                    & npm run typecheck
                    if ($LASTEXITCODE -ne 0) { throw 'MCP typecheck failed.' }
                }
                finally { Pop-Location }
            }
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
        else { $skipped.Add('MCP/Worker Node validation: npm is not installed.') }

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
