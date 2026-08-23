---
name: private-proxy-manager
description: Operate Private Proxy Manager from natural-language intent. Use when a user provides this repository URL or asks to create, inspect, repair, migrate, render, back up, or recover a supported private proxy route. The agent discovers capabilities and operates the deterministic local machine surface so the user does not need to learn the repository or schema.
---

# Private Proxy Manager

PPM turns user intent into validated local state, scoped infrastructure operations, remote audit, and private client output.

The governing rule is:

> **The agent owns the project workflow, not the user's authority.**

## Start from a repository URL

When the user gives you the repository or asks to use PPM:

1. Open or safely clone the supplied repository.
2. Read root `AGENTS.md` and this Skill.
3. Run `agent/ppm-agent.ps1 capabilities`; do not infer support from external product features.
4. Run `scripts/Validate-Local.ps1 -Quick` before accepting real infrastructure context.
5. Bootstrap only if private state is absent.
6. Inspect sanitized context and drift before changing existing state.
7. Explain the dedicated-host prerequisites and host-wide effects.
8. Gather only the facts required for the user's desired Route and ClientTarget.
9. Run scoped preflight and execute only when `ready=true`.
10. Audit and render after meaningful changes, then report the outcome without secret-bearing details.

Representative machine calls are in [references/operations.md](references/operations.md). These are internal operations, not commands the user must learn.

## Preflight

Never mutate from an unverified guess. For the current operation, establish the goal, exact target, relevant desired and observed state, required access, supported capability, expected effects, conflicts, and authorization class.

If preflight is blocked:

- continue safe read-only discovery when possible;
- use authoritative current sources for time-sensitive facts;
- ask the smallest necessary question when the fact cannot be discovered;
- do not invent credentials, ownership, provider state, purchase decisions, or destructive intent.

## Product model

- `Server`: BYO dedicated, rebuildable Ubuntu 24.04 amd64 compute over SSH.
- `Link`: single-hop WireGuard connection between two Servers.
- `Route`: direct or relay private exit with Hysteria2 ingress.
- `Provider`: optional generic Mihomo HTTP node source stored as a local secret.
- `Profile`: reusable Route, Provider, and policy selection.
- `ClientTarget`: renderer and delivery identity referencing a Profile.
- `desired`: canonical inventory schema 1.
- `observed`: disposable sanitized audit evidence.
- `private secrets`: canonical local credentials and delivery state.

Bootstrap creates neutral state and waits for actual context before adding Profiles or ClientTargets.

The supported host preparation changes UFW, swap/fstab, SMTP egress, SSH/sysctl/journald, packages, unattended-upgrades, and vnstat. Confirm a dedicated rebuildable host before remote deployment. See `docs/COMPATIBILITY.md` for the current stack.

## Execution

Prefer PPM-owned deterministic operations over arbitrary shell or free-form SSH. Use raw SSH only for necessary read-only diagnosis when PPM has no bounded equivalent.

Remote mutation and uninstall stay inside the PPM ownership boundary. Unrelated Hysteria, Xray, WireGuard, firewall, service, package, account, and host-file state is not a cleanup target.

Typed drift does not grant repair authority. Diagnose the category and use a supported scoped operation.

For client behavior, see [references/clients.md](references/clients.md). For migration and recovery, see [references/migration-recovery.md](references/migration-recovery.md).

## Subscription authority

Private subscription state belongs to one Shadowrocket ClientTarget and uses an isolated Worker/host identity.

`rotate-subscription-token` is a `credential-change`. It requires explicit current approval, is excluded from generic MCP execute, and must leave Route and other ClientTarget credentials unchanged.

## External facts

Use current authoritative web or browser sources for facts that can change, including VPS offerings, firewall requirements, and client import behavior. Research supplies evidence only; map the conclusion back to implemented PPM capabilities and current user authority.

See [references/research.md](references/research.md).

## Secrets and output

Do not put tokens, keys, subscription URLs, live node URIs, server addresses, local key paths, generated configs, or raw remote diagnostics in chat unless one exact disclosure is necessary and explicitly requested.

The chosen cloud model may receive tool arguments such as a server address, SSH username, key path, and selected IDs. Prefer non-identifying IDs and an offline runtime when these inputs must remain local.

Use sanitized machine results, keep raw evidence local, and tell the user:

- what changed;
- what was validated;
- what remains blocked or undecided;
- any meaningful host, privacy, or availability effect.

When a requested outcome is absent from capability discovery, explain that gap. Extend the deterministic core with an explicit operation and tests when the product should support it; do not improvise a hidden parallel system.
