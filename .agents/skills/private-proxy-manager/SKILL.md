---
name: private-proxy-manager
description: Operate Private Proxy Manager through natural-language intent. Use when a user gives this repository URL, asks to set up or manage a private proxy network, add or replace VPS routes, configure supported clients, inspect drift/security, publish the optional private subscription, recover state, or asks the AI to take care of the project. The normal user should not need proxy, networking, schema, or command knowledge.
---

# Private Proxy Manager

Private Proxy Manager (PPM) is agent-native infrastructure software. The human expresses intent; the agent gathers context, researches current facts when needed, and delegates execution to PPM's deterministic local operations.

The product rule is:

> **The agent owns the project workflow, not the user's authority.**

## Start here

When the user gives you the repository or says they want to use PPM:

1. Read the root `AGENTS.md` and this Skill. Do not make the human explain the repository structure.
2. If the repository is not local and your runtime can safely clone/open it from the supplied URL, do so. Otherwise ask only for the minimum action needed to make the repository accessible.
3. Treat `agent/ppm-agent.ps1` as the stable machine surface. Scripts and PowerShell commands are implementation interfaces for agents/contributors, not a workflow to teach the user.
4. Inspect capabilities before assuming support.
5. Bootstrap clean private state if it does not exist. Clean bootstrap is neutral: it does not choose geography, Provider, Profile policy, client application/device targets, or subscription delivery.
6. Inspect sanitized context and drift before proposing changes to an existing setup.
7. Gather missing context using read-only local inspection and authoritative web/browser research where relevant.
8. Create the actual Profiles and ClientTargets only after the user's network/client needs are known.
9. Before every mutation, run the scoped preflight. **Do not execute unless `ready` is true.**
10. After meaningful remote changes, validate/audit and report the outcome without dumping secrets or low-level implementation details.

Representative internal machine calls are described in [references/operations.md](references/operations.md). Do not turn them into user-facing onboarding instructions.

## Context Completeness Gate

Never mutate because a guess seems plausible. For the scoped action, establish enough verified context to identify the user's goal, target, relevant desired/observed state, supported capability, required access, expected effects, authorization class, and any decision that genuinely belongs to the user.

`complete context` means sufficient verified context for the current operation, not exhaustive knowledge of the whole project.

If preflight reports missing context or conflicts:

- continue safe read-only discovery where possible;
- use current authoritative external information when the missing fact is version-sensitive;
- ask the smallest necessary user question only when the fact cannot be discovered safely;
- never invent credentials, ownership, provider state, destructive intent, or a purchase decision.

## Operating modes

PPM supports `collaborative` and `steward` modes.

In collaborative mode, explain meaningful choices before carrying them out when helpful.

In Steward Mode, take responsibility for routine technical operation: gather context, research, choose safe defaults, maintain desired state, run supported non-destructive operations covered by the user's goal, validate, diagnose, and keep supported client artifacts consistent. Minimize unnecessary questions.

Steward Mode is **not** blanket authorization. It never silently authorizes purchases, cloud/VPS deletion, destructive retirement of a working route, credential rotation with user-visible blast radius, unrelated account/cloud mutations, or material cost/privacy/performance choices that need the user's preference.

See [references/security.md](references/security.md).

## Product/domain model

The agent should understand these concepts so the user usually does not have to:

- `Server`: bring-your-own dedicated, rebuildable Ubuntu 24.04 amd64 compute with stable identity and SSH access; current compute driver is `byo-ssh` and `host_ownership` must be `dedicated`.
- `Link`: an explicit inter-server link; current driver is single-hop WireGuard.
- `Route`: a private logical exit; current ingress driver is Hysteria2 and topology is direct or single-hop relay.
- `Provider`: an optional third-party node source; current source type is generic Mihomo HTTP. PPM must work with zero Providers.
- `Profile`: reusable Route / Provider / policy selection. It is **not** a renderer or device identity.
- `ClientTarget`: references a Profile and owns renderer/delivery identity (`mihomo` or `shadowrocket` initially).
- `desired`: canonical local configuration using public inventory schema `1`.
- `observed`: disposable, sanitized audit evidence that can be regenerated.
- `client render state`: local hashes used only to identify stale/missing canonical ClientTarget output.
- `private secrets`: local canonical credentials and delivery state; never source them from chat history.

The initial supported infrastructure stack is intentionally narrow: Hysteria2 ingress, WireGuard single-hop relay, BYO SSH-accessible supported Linux servers, optional generic Providers, Mihomo/Clash Verge-compatible output, and Shadowrocket output.

The server preparation step has host-wide effects, including UFW defaults, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat changes. It is not supported on a shared production host. Uninstall removes PPM-owned artifacts and named policy files but does not restore unknown prior host-wide state.

Do not promise an unsupported protocol, provider, client renderer, or cloud lifecycle driver merely because external documentation says it exists. See `docs/COMPATIBILITY.md`.

## Execution discipline

Prefer PPM-owned deterministic operations over arbitrary shell or free-form SSH.

Use raw SSH only for read-only diagnosis when there is no PPM-owned equivalent and the evidence is necessary. Do not use ad-hoc SSH configuration as a substitute for adding a missing core capability.

Never hand-edit canonical private JSON/YAML merely to get past a validation failure. Use the supported operation or fix the product implementation.

Remote mutation and uninstall must touch only PPM-owned resources. The presence of unrelated Xray, Hysteria, WireGuard, or other networking software is not permission to remove or disable it.

Do not automatically self-heal drift. Typed drift may identify service, configuration, firewall/network, WireGuard, Hysteria2/certificate, egress, ClientTarget-render, or undetermined state. Diagnose it and apply a scoped operation only when the user's goal/authorization covers the change.

For client selection/rendering, see [references/clients.md](references/clients.md).

The model runtime may see the tool arguments required for an operation, including a server IP, SSH username, local key path, and selected IDs. Returned artifact paths are private-root-relative and raw diagnostics are suppressed, but local-first is not a promise of zero model-visible metadata. Use an offline runtime when those values must remain local.

For migration and recovery, see [references/migration-recovery.md](references/migration-recovery.md).

## Subscription authority

Shadowrocket subscription state is ClientTarget-scoped. Each subscription target requires an isolated Worker/host identity.

Subscription-token rotation is a `credential-change` operation. It is intentionally not available through the generic MCP execute tool. Only perform it after explicit current authorization; it must not rotate Route credentials or unrelated ClientTarget credentials.

## External research

Use current authoritative web/browser sources when the task depends on facts that can change, such as VPS regions/prices, provider firewall requirements, client import support, current protocol/client compatibility, or cloud documentation.

Research is evidence, not permission. It does not authorize a purchase, account change, cloud mutation, destructive action, or a capability PPM has not implemented.

If your runtime has no web/browser capability, proceed with local capability truth and ask for the missing current fact rather than fabricating it.

See [references/research.md](references/research.md).

## Secrets and conversational output

Do not paste tokens, private keys, subscription URLs, auth strings, full live node URIs, server IPs, SSH key paths, or secret-bearing generated configs into the conversation unless the user explicitly needs one exact value and disclosure is necessary for the task.

Prefer sanitized machine results from `agent/ppm-agent.ps1`. Keep raw evidence local.

Tell the user what changed, what was validated, what still needs their decision, and any meaningful risk. Hide incidental implementation complexity.

## Unsupported or unsafe requests

If the request is outside PPM capabilities, say what is unsupported instead of improvising a parallel system.

If a capability should exist in PPM, improve the deterministic core rather than teaching the user a manual workaround.

Never convert PPM into a GUI/panel/TUI, hosted management control plane, reseller/billing system, traffic-surveillance platform, or generic MCP wrapper around another proxy panel as a shortcut for the requested product behavior.
