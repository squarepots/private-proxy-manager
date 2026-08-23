# Private Proxy Manager agent contract

Private Proxy Manager (PPM) is agent-native infrastructure software. Natural-language conversation with a capable AI agent is the only first-class user interface.

## Canonical instructions

Activate/read `.agents/skills/private-proxy-manager/SKILL.md` before operating this project. That Skill is model-neutral and owns the product workflow, Context Completeness Gate, Steward Mode, external-research boundary, client behavior, infrastructure migration/recovery behavior, and security rules.

Do not duplicate those rules in runtime-specific instruction files.

## Machine surface

Use `agent/ppm-agent.ps1` for structured capability discovery, clean bootstrap, sanitized context, drift, preflight, operating mode, and execution.

The PowerShell engine, server deploy scripts, renderers, and Worker are implementation surfaces for agents and contributors; do not teach them to the normal user as a command-driven product workflow.

Before every mutation, use scoped preflight and proceed only when `ready` is true. Prefer structured context via stdin when appropriate.

## Final object model

Keep these boundaries explicit:

- Server -> `compute.driver=byo-ssh` in the initial implementation;
- Link -> `driver=wireguard`;
- Route -> `ingress.driver=hysteria2`;
- Provider -> optional generic `source_type=mihomo-http` with private source URL;
- Profile -> reusable Route / Provider / policy selection;
- ClientTarget -> renderer/delivery identity that references a Profile.

A Profile is not a device or renderer identity. `ClientTarget.renderer` is authoritative. Do not reintroduce OS-specific renderer abstractions into the core.

Clean bootstrap is neutral: it does not choose a Provider, geography, Profile policy, client application/device target, subscription identity, or AI vendor. Gather context first, then create the actual Profiles and ClientTargets the user needs.

## Private/public boundary

Tracked files must contain reusable code, tests, public documentation, release metadata, portable agent instructions/adapters, and sanitized examples only.

Private instance state may live under ignored local `private/` or another explicitly selected private root. It may contain real inventory, observed evidence, credentials, provider/subscription URLs, SSH material, generated client artifacts, and recovery archives. Never commit or paste that material into issues, logs, chat, examples, or documentation.

Do not inspect more private state than the current task requires.

## Execution boundary

Prefer repository-owned deterministic operations over ad-hoc SSH/configuration. Read-only diagnosis may gather missing evidence; it must not become an alternate configuration system.

Typed drift is evidence, not repair authority. Do not automatically self-heal or overwrite a deployed Route whose state is drifted or undetermined.

Remote deployment and uninstall may mutate only PPM-owned resources. The supported host is a dedicated, rebuildable Ubuntu 24.04 amd64 VPS because setup also changes host-wide UFW, swap/fstab, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state. Do not delete, disable, or require the absence of unrelated proxy software or unrelated WireGuard configuration merely because PPM can detect it; uninstall does not restore unknown prior host-wide state.

Do not add a GUI/dashboard/TUI/panel or make the internal command surface a competing user interface.

Do not add billing, quotas, reseller/customer management, telemetry, traffic history, or a hosted PPM control plane as part of the personal product.

## Compatibility boundary

The core must not branch on AI vendor/model identity. Runtime-specific files are integration targets, not product dependencies.

The initial infrastructure scope is deliberately narrow: Hysteria2 ingress, WireGuard single-hop relay, BYO supported Linux server over SSH, optional generic Provider, Mihomo-compatible output, Shadowrocket output, and optional private Cloudflare subscription delivery.

The public desired-state contract starts at inventory schema `1`. Do not add compatibility machinery for development-only schemas that were never part of a public release. Product SemVer and the state schema remain separate compatibility domains.

Use `docs/COMPATIBILITY.md` and machine capability discovery as explicit capability truth. Do not claim unsupported protocol/client/provider/compute capabilities merely because an external product supports them.

## Subscription boundary

Subscription state is ClientTarget-scoped. Each subscription-backed Shadowrocket ClientTarget requires an isolated Worker/host identity under the current Worker design.

Subscription-token rotation is a `credential-change` operation. It requires explicit current user authority and is intentionally excluded from generic MCP execute. Rotation must not change Route credentials or another ClientTarget's credentials.

## Safety

The governing rule is:

> **The agent owns the project workflow, not the user's authority.**

Steward Mode can make routine safe technical decisions, but purchases, destructive cloud/server lifecycle changes, credential rotation with user-visible blast radius, unrelated account/cloud mutations, and material preference tradeoffs still require explicit current user authority.

Infrastructure migration is overlap-first. Never equate migration with immediate deletion of working capacity.

## Git and release boundary

Repository modification, commits, pushes, pull requests, merges, tags, and releases are governed by the active user's current authorization and the host agent's Git safety rules. Never infer standing publication authority from this file.

Treat the tracked tree as public source: do not copy private operational state, credentials, generated artifacts, ignored runtime state, or non-product provenance into commits or release notes.

Product SemVer is read from `version.txt`; state schema is a separate compatibility domain.

Before a PR is ready to merge:

1. Review the final diff.
2. Ensure the branch is current with the latest target branch.
3. Classify version impact as exactly one of `none`, `patch`, `minor`, or `major`.
4. Record that decision and a short reason in the PR body.
5. Set the final product version from the current target-branch version: `none` leaves it unchanged; otherwise run `scripts/Bump-Version.ps1` with the chosen impact so the branch contains exactly the patch/minor/major successor of the current base.
6. Do not bump versions per commit, push, or intermediate work.
7. If the target branch advances or the final scope changes before merge, recompute from the new base rather than stacking another bump on a provisional branch version.

The PR body records the decision for review; CI and release automation do not infer SemVer from it. Follow `docs/RELEASING.md` for the repository-owned release flow.
