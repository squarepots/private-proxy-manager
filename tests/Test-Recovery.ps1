[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }

function Find-SevenZip {
    foreach ($name in '7z','7zz','7z.exe') {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    if ($env:OS -eq 'Windows_NT') {
        foreach ($candidate in @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path $env:ProgramFiles 'NanaZip\7z.exe'))) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
        }
    }
    throw '7-Zip is required for the recovery test.'
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sevenZip = Find-SevenZip
$root = Join-Path ([IO.Path]::GetTempPath()) ('ppm-recovery-test-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $root 'stage'
$extract = Join-Path $root 'extract'
$archive = Join-Path $root 'fixture.7z'
$fixturePassword = 'ppm-public-fixture-password'
try {
    New-Item -ItemType Directory -Path (Join-Path $stage 'private') -Force | Out-Null
    $fixture = Join-Path $stage 'private\inventory.json'
    [IO.File]::WriteAllText($fixture, '{"schema":1,"fixture":true}', [Text.UTF8Encoding]::new($false))
    $expectedHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
    [IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS'), ($expectedHash.ToLowerInvariant() + '  private/inventory.json'), [Text.UTF8Encoding]::new($false))

    & $sevenZip a -t7z -mhe=on -mx=1 ("-p$fixturePassword") -- $archive (Join-Path $stage '*') | Out-Null
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archive -PathType Leaf)) 'Encrypted recovery fixture was not created.'

    $wrongOutput = (& $sevenZip l -pdefinitely-wrong -- $archive 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -ne 0) 'An incorrect recovery password unexpectedly succeeded.'
    Assert-True ($wrongOutput -notmatch 'inventory\.json|SHA256SUMS') 'Encrypted archive exposed filenames without the correct password.'

    New-Item -ItemType Directory -Path $extract | Out-Null
    & $sevenZip x ("-p$fixturePassword") ("-o$extract") -y -- $archive | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Correct recovery password could not extract the archive.'
    $actualHash = (Get-FileHash -LiteralPath (Join-Path $extract 'private\inventory.json') -Algorithm SHA256).Hash
    Assert-True ($actualHash -eq $expectedHash) 'Recovered fixture hash does not match its manifest source.'

    $backupSource = [IO.File]::ReadAllText((Join-Path $repo 'scripts\New-RecoveryArchive.ps1'), [Text.Encoding]::UTF8)
    Assert-True ($backupSource -match '(?m)^\s*& \$sevenZip a .* -p -- \$archive') 'Production backup must let 7-Zip prompt for the password.'
    Assert-True ($backupSource -notmatch '(?i)\[string\]\s*\$Password|\$env:.*password') 'Production backup accepts a password through an unsafe channel.'
    Assert-True ($backupSource -match '(?s)finally\s*\{.*Remove-Item.*-Recurse') 'Production backup does not guarantee plaintext staging cleanup.'

    $restoreSource = [IO.File]::ReadAllText((Join-Path $repo 'scripts\Restore-RecoveryArchive.ps1'), [Text.Encoding]::UTF8)
    Assert-True ($restoreSource -match '(?m)^\s*& \$sevenZip x -p ') 'Production restore must let 7-Zip prompt for the password locally.'
    Assert-True ($restoreSource -notmatch '(?i)\[string\]\s*\$Password|\$env:.*password') 'Production restore accepts a password through an unsafe channel.'

    Write-Host 'Portable encrypted backup/recovery password-channel, header-encryption, and plaintext-cleanup tests passed.'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
