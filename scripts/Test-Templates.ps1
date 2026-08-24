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
Require-Text 'server/install-path-components.sh' 'HYSTERIA_VERSION=v2\.9\.3' 'The supported Hysteria2 binary is not pinned.'
Require-Text 'server/install-path-components.sh' 'HYSTERIA_SHA256=[0-9a-f]{64}' 'The supported Hysteria2 binary is not hash-pinned.'
Require-Text 'server/install-path-components.sh' 'RST_BIN_DIR=/usr/local/lib/route-steward' 'The RST-owned binary namespace is missing.'
Require-Text 'server/install-path-components.sh' 'HYSTERIA_BIN=\$\{RST_BIN_DIR\}/hysteria' 'Hysteria2 is not installed inside the RST-owned namespace.'
Require-Text 'server/config/99-route-steward-ssh.conf' 'PasswordAuthentication no' 'SSH password login is not disabled.'
Require-Text 'server/config/route-steward-hysteria.service' 'User=route-steward-hysteria' 'Direct-route service does not use the RST-owned runtime identity.'
Require-Text 'server/configure-relay-entry.sh' 'bindDevice:\s*\$\{INTERFACE\}' 'Relay ingress is not bound to its WireGuard interface.'
Require-Text 'server/configure-relay-entry.sh' 'Requires=wg-quick@\$\{INTERFACE\}' 'Relay service does not require its WireGuard interface.'
Require-Text 'server/configure-relay-exit.sh' 'POSTROUTING.+MASQUERADE' 'Relay exit NAT is missing.'
Require-Text 'server/base-setup.sh' '/etc/modules-load.d/route-steward-bbr\.conf' 'Modules-load policy is not installed under a RST-owned name.'
Require-Text 'server/base-setup.sh' '/etc/systemd/journald\.conf\.d/99-route-steward\.conf' 'Journald policy is not installed under a RST-owned name.'
Require-Text 'server/base-setup.sh' '/etc/apt/apt\.conf\.d/52-route-steward-unattended-upgrades' 'Unattended-upgrades policy is not installed under a RST-owned name.'
Require-Text 'server/uninstall.sh' '/etc/modules-load.d/route-steward-bbr\.conf' 'Uninstall does not target the RST-owned modules-load policy.'
Require-Text 'server/uninstall.sh' '/etc/systemd/journald\.conf\.d/99-route-steward\.conf' 'Uninstall does not target the RST-owned journald policy.'
Require-Text 'server/uninstall.sh' '/etc/apt/apt\.conf\.d/52-route-steward-unattended-upgrades' 'Uninstall does not target the RST-owned unattended-upgrades policy.'
Reject-Text 'server/base-setup.sh' 'ufw --force reset' 'Base deployment must not erase unrelated firewall rules.'
Reject-Text 'server/configure-relay-exit.sh' 'ufw --force reset' 'Relay deployment must not erase unrelated firewall rules.'
Reject-Text 'server/configure-ingress.sh' '(?i)\b(?:reality|vless)\b' 'Unsupported Reality/VLESS leaked into the supported direct-route path.'
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
Require-Text 'internal/steward/subscription.go' '"ci", "--ignore-scripts", "--no-audit", "--no-fund"' 'Standalone publication does not install the embedded Worker lockfile.'
Require-Text 'internal/steward/subscription.go' '"--no-install", "wrangler"' 'Standalone publication may resolve an unpinned transient Wrangler tree.'
Reject-Text 'internal/steward/subscription.go' 'wrangler@|--yes' 'Standalone publication must not bypass the embedded Worker lockfile.'

# Standard hosted CI is PR/manual only. Dependency installation remains reproducible.
Require-Text '.github/workflows/ci.yml' '(?m)^\s*pull_request:\s*$' 'Standard CI is missing the PR validation boundary.'
Require-Text '.github/workflows/ci.yml' 'types:\s*\[opened, reopened, synchronize\]' 'Standard CI does not use the bounded PR lifecycle.'
Require-Text '.github/workflows/ci.yml' '(?m)^\s*workflow_dispatch:\s*$' 'Manual validation trigger is missing.'
Reject-Text '.github/workflows/ci.yml' '(?m)^\s*push:\s*$' 'Standard CI must not run on push.'
Require-Text '.github/workflows/ci.yml' 'cancel-in-progress:\s*true' 'Superseded validation runs are not cancelled.'
Require-Text '.github/workflows/ci.yml' 'go test ./\.\.\.' 'The native Go control plane is not tested.'
Require-Text '.github/workflows/ci.yml' 'Build-ReleaseArtifacts\.sh' 'The real release archives are not validated in CI.'
Require-Text '.github/workflows/release.yml' 'Build-ReleaseArtifacts\.sh' 'The release workflow does not use the validated archive builder.'
Require-Text 'scripts/Build-ReleaseArtifacts.sh' 'linux/amd64 linux/arm64 darwin/amd64 darwin/arm64 windows/amd64 windows/arm64' 'The six supported release targets are incomplete.'
Require-Text '.github/workflows/release.yml' 'ref:\s*\$\{\{ github\.sha \}\}' 'Release checkout is not pinned to the workflow event SHA.'
Require-Text '.github/workflows/release.yml' 'git tag -a "\$tag" -m "\$tag" "\$EVENT_SHA"' 'Release tag is not created from the immutable workflow event SHA.'
Reject-Text '.github/workflows/release.yml' 'git pull' 'Release workflow must not replace the event source with moving branch state.'

# Product identity and positioning are canonical across the public tree.
Require-Text 'README.md' 'Set up and manage private proxies on your own servers with an AI agent\.' 'The canonical English product statement is missing.'
Require-Text 'README.md' 'Route Steward helps an AI agent set up, inspect, change, and recover a private proxy on VPS servers you control\.' 'The canonical English product definition is missing.'
Require-Text 'README.zh-CN.md' '用 AI agent 在自己的服务器上搭建和管理私有代理。' 'The canonical Chinese product statement is missing.'
Require-Text 'README.zh-CN.md' 'Route Steward 帮助 AI agent 在你控制的 VPS 上搭建、检查、更换和恢复私有代理。' 'The canonical Chinese product definition is missing.'
Require-Text 'docs/OPERATING-BOUNDARY.md' 'owned by the operator or administered with the resource owner''s authorization' 'The authorized-infrastructure operating boundary is missing.'
Require-Text 'internal/steward/engine.go' '"interface":\s*"agent-machine-surface"' 'The native machine surface product identity is incorrect.'
Reject-Text 'agent/route-steward-agent.ps1' "'run', './cmd/route-steward', '--'" 'The Go source fallback must not pass a fake -- command.'
Reject-Text '.agents/skills/route-steward/SKILL.md' 'go run ./cmd/route-steward --' 'The repository-URL workflow must use the real Go CLI command shape.'

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
Write-Host 'Static server ownership/safety, Worker privacy, CI trigger, documentation, portability, and compatibility validation passed.'
