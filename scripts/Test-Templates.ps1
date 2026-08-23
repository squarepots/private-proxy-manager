[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [Collections.Generic.List[string]]::new()

function Require-Text([string]$RelativePath, [string]$Pattern, [string]$Message) {
    $path = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $script:failures.Add("${RelativePath}: required file is missing."); return }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -notmatch $Pattern) { $script:failures.Add("${RelativePath}: $Message") }
}

function Reject-Text([string]$RelativePath, [string]$Pattern, [string]$Message) {
    $path = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -match $Pattern) { $script:failures.Add("${RelativePath}: $Message") }
}

# Static server safety properties that are naturally proven from the mutation scripts.
Require-Text 'server/install-proxy-binaries.sh' 'HYSTERIA_VERSION=v2\.9\.3' 'The supported Hysteria2 binary is not pinned.'
Require-Text 'server/install-proxy-binaries.sh' 'HYSTERIA_SHA256=[0-9a-f]{64}' 'The supported Hysteria2 binary is not hash-pinned.'
Require-Text 'server/install-proxy-binaries.sh' 'PPM_BIN_DIR=/usr/local/lib/private-proxy-manager' 'The PPM-owned binary namespace is missing.'
Require-Text 'server/install-proxy-binaries.sh' 'HYSTERIA_BIN=\$\{PPM_BIN_DIR\}/hysteria' 'Hysteria2 is not installed inside the PPM-owned namespace.'
Require-Text 'server/config/99-private-proxy-manager-ssh.conf' 'PasswordAuthentication no' 'SSH password login is not disabled.'
Require-Text 'server/config/private-proxy-manager-hysteria.service' 'User=ppm-hysteria' 'Direct-route service does not use the PPM-owned runtime identity.'
Require-Text 'server/configure-relay-entry.sh' 'bindDevice:\s*\$\{INTERFACE\}' 'Relay ingress is not bound to its WireGuard interface.'
Require-Text 'server/configure-relay-entry.sh' 'Requires=wg-quick@\$\{INTERFACE\}' 'Relay service does not require its WireGuard interface.'
Require-Text 'server/configure-relay-exit.sh' 'POSTROUTING.+MASQUERADE' 'Relay exit NAT is missing.'
Require-Text 'server/base-setup.sh' '/etc/modules-load.d/private-proxy-manager-bbr\.conf' 'Modules-load policy is not installed under a PPM-owned name.'
Require-Text 'server/base-setup.sh' '/etc/systemd/journald\.conf\.d/99-private-proxy-manager\.conf' 'Journald policy is not installed under a PPM-owned name.'
Require-Text 'server/base-setup.sh' '/etc/apt/apt\.conf\.d/52-private-proxy-manager-unattended-upgrades' 'Unattended-upgrades policy is not installed under a PPM-owned name.'
Require-Text 'server/uninstall.sh' '/etc/modules-load.d/private-proxy-manager-bbr\.conf' 'Uninstall does not target the PPM-owned modules-load policy.'
Require-Text 'server/uninstall.sh' '/etc/systemd/journald\.conf\.d/99-private-proxy-manager\.conf' 'Uninstall does not target the PPM-owned journald policy.'
Require-Text 'server/uninstall.sh' '/etc/apt/apt\.conf\.d/52-private-proxy-manager-unattended-upgrades' 'Uninstall does not target the PPM-owned unattended-upgrades policy.'
Reject-Text 'server/base-setup.sh' 'ufw --force reset' 'Base deployment must not erase unrelated firewall rules.'
Reject-Text 'server/configure-relay-exit.sh' 'ufw --force reset' 'Relay deployment must not erase unrelated firewall rules.'
Reject-Text 'server/configure-proxies.sh' '(?i)\b(?:reality|vless)\b' 'Unsupported Reality/VLESS leaked into the supported direct-route path.'
Reject-Text 'server/configure-relay-entry.sh' '(?i)\b(?:reality|vless)\b' 'Unsupported Reality/VLESS leaked into the supported relay path.'
Reject-Text 'server/uninstall.sh' 'ufw --force reset|swapoff|apt(?:-get)?\s+remove' 'Uninstall must not reset or remove unrelated host state.'
Reject-Text 'server/uninstall.sh' '(?:/usr/local/bin/hysteria|/etc/hysteria|/var/lib/hysteria|/usr/local/bin/xray|/etc/xray|/var/lib/xray)' 'Uninstall must not delete generic or unrelated proxy software state.'
Reject-Text 'server/uninstall.sh' '(?:/etc/modules-load\.d/bbr\.conf|/etc/systemd/journald\.conf\.d/99-limits\.conf|/etc/apt/apt\.conf\.d/52unattended-upgrades-local)' 'Uninstall must not delete generic host policy filenames.'
Reject-Text 'server/audit.sh' '(?:/usr/local/bin/xray|/etc/xray|/var/lib/xray|xray\.service)' 'Direct audit must not require unrelated Xray to be absent.'
Reject-Text 'server/audit-relay.sh' '(?:/usr/local/bin/xray|/etc/xray|/var/lib/xray|xray-relay)' 'Relay audit must not require unrelated Xray to be absent.'

# The private subscription Worker is intentionally a narrow no-log/no-cache surface.
Require-Text 'worker/wrangler.jsonc' '"preview_urls": false' 'Worker preview URLs must be disabled.'
Require-Text 'worker/wrangler.jsonc' '"enabled": false' 'Worker observability must remain disabled.'
Require-Text 'worker/src/index.ts' 'timingSafeEqual' 'Worker token comparison is not timing safe.'
Require-Text 'worker/src/index.ts' 'private, no-store, max-age=0' 'Worker responses must not be cached.'
Reject-Text 'worker/src/index.ts' 'console\.(?:log|debug|info|warn|error)' 'Worker must not log private subscription requests.'

# Standard hosted CI is PR/manual only. Dependency installation remains reproducible.
Require-Text '.github/workflows/ci.yml' '(?m)^\s*pull_request:\s*$' 'Standard CI is missing the PR validation boundary.'
Require-Text '.github/workflows/ci.yml' 'types:\s*\[opened, reopened, synchronize\]' 'Standard CI does not use the bounded PR lifecycle.'
Require-Text '.github/workflows/ci.yml' '(?m)^\s*workflow_dispatch:\s*$' 'Manual validation trigger is missing.'
Reject-Text '.github/workflows/ci.yml' '(?m)^\s*push:\s*$' 'Standard CI must not run on push.'
Require-Text '.github/workflows/ci.yml' 'cancel-in-progress:\s*true' 'Superseded validation runs are not cancelled.'
Require-Text '.github/workflows/ci.yml' 'npm ci --ignore-scripts' 'MCP dependencies are not installed reproducibly from the lockfile.'
Require-Text '.github/workflows/release.yml' 'ref:\s*\$\{\{ github\.sha \}\}' 'Release checkout is not pinned to the workflow event SHA.'
Require-Text '.github/workflows/release.yml' 'git tag -a "\$tag" -m "\$tag" "\$EVENT_SHA"' 'Release tag is not created from the immutable workflow event SHA.'
Reject-Text '.github/workflows/release.yml' 'git pull' 'Release workflow must not replace the event source with moving branch state.'

# GFM treats CJK text immediately after a bare URL as part of the link target.
$unsafeCjkAutolinkPattern = 'https?://[A-Za-z0-9._~:/?#\[\]@!$&''()*+,;=%-]+(?=[\p{IsCJKUnifiedIdeographs}\u3000-\u303F\uFF00-\uFFEF])'
$markdownFiles = @(& git -C $repo ls-files -- '*.md')
if ($LASTEXITCODE -ne 0) { $failures.Add('Unable to enumerate tracked Markdown files.') }
foreach ($relativePath in $markdownFiles) {
    $lines = [IO.File]::ReadAllLines((Join-Path $repo $relativePath), [Text.Encoding]::UTF8)
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex] -match $unsafeCjkAutolinkPattern) {
            $failures.Add("${relativePath}:$($lineIndex + 1): bare URL runs into CJK text.")
        }
    }
}

$examplePath = Join-Path $repo 'examples/inventory.example.json'
if (Test-Path -LiteralPath $examplePath -PathType Leaf) {
    try {
        $example = [IO.File]::ReadAllText($examplePath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([int]$example.schema -ne 1) { $failures.Add('examples/inventory.example.json: public inventory schema must be 1.') }
    }
    catch { $failures.Add('examples/inventory.example.json: invalid JSON.') }
}
else { $failures.Add('examples/inventory.example.json: required file is missing.') }

$psFiles = Get-ChildItem -Path $repo -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '[\\/](?:private|\.cache|node_modules)[\\/]' }
$strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
foreach ($file in $psFiles) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    try { $null = $strictUtf8.GetString($bytes) }
    catch { $failures.Add("$($file.FullName): file is not valid UTF-8.") }
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) { $failures.Add("$($file.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)") }
}

if ($failures.Count) {
    $failures | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host 'Static server ownership/safety, Worker privacy, CI trigger, documentation, portability, and PowerShell validation passed.'
