# Compatibility

This document describes **current PPM capability truth**. It is not a roadmap. A protocol/client/provider feature is unsupported until the deterministic core, validation, and tests implement it.

## Infrastructure

| Capability | Status | Notes |
| --- | --- | --- |
| BYO dedicated Linux server over SSH | Supported | Exact baseline: rebuildable Ubuntu 24.04 amd64; `compute.driver=byo-ssh` and `compute.host_ownership=dedicated` are required. |
| Hysteria2 ingress | Supported | Exact binary version/hash is pinned by repository deployment code. |
| Direct Route | Supported | Client → Hysteria2 Server → declared exit. |
| Single-hop relay | Supported | Client → Hysteria2 entry → WireGuard Link → exit/NAT. |
| Multi-hop relay | Not supported | Current Link model is intentionally single-hop. |
| Automatic cloud/VPS provisioning | Not supported | Purchasing/provisioning external compute is outside the current deterministic core. |
| Automatic destructive server retirement | Not supported | External deletion requires explicit user authority and is not generic PPM execution. |

## Desired state

The current persisted desired-state contract is inventory schema `1`.

Schema 1 directly expresses:

- Server with `compute.driver=byo-ssh`;
- Link with `driver=wireguard`;
- Route with `ingress.driver=hysteria2`;
- optional Provider with `source_type=mihomo-http`;
- Profile for reusable Route / Provider / policy selection;
- ClientTarget for concrete renderer/delivery identity.

PPM does not publish compatibility code for development-only state schemas that were never part of a public release. Recovery accepts the current public schema only.

Product SemVer in `version.txt` is independent of desired-state schema compatibility.

## Bootstrap

Clean bootstrap is supported and intentionally neutral. It creates valid schema-1 private state but does not assume compute/provider/region, a routing geography or selected policy, a Profile, a device/client application, a Provider/subscription, or an AI/model vendor.

The agent gathers actual context and explicitly creates Profiles and ClientTargets afterward.

## Clients and rendering

| Capability | Status | Notes |
| --- | --- | --- |
| Mihomo / Clash Verge-compatible file output | Supported | Private Hysteria2 Routes; optional explicitly selected generic Providers. |
| Shadowrocket node import | Supported | Offline private import generated from selected Hysteria2 Routes. |
| Shadowrocket private subscription | Supported | Optional isolated ClientTarget-scoped Cloudflare Worker delivery. |
| Other client renderers | Not supported | External client compatibility does not imply a PPM renderer exists. |
| Automated GUI control | Not supported | PPM renders/imports configuration; it does not drive client GUIs. |

With no explicit Profile policy, Mihomo uses generic privacy routing/DNS behavior. `balanced-cn` is available only as an explicit opt-in policy; it is not a bootstrap/default geography assumption.

## Providers

A `mihomo-http` Provider is supported as an **optional** upstream node source. PPM must remain functional with zero Providers.

Provider URLs remain in local secret storage and are not returned by sanitized agent context. Other Provider source types are not supported.

## Agent interfaces

| Interface | Status | Notes |
| --- | --- | --- |
| `agent/ppm-agent.ps1` | Supported | Canonical sanitized machine surface. |
| Repository Skill | Supported | Canonical model-neutral operating instructions. |
| Local stdio MCP adapter | Supported | Thin adapter over the canonical machine surface; no duplicate business logic. |
| Model/vendor-specific core behavior | Not supported | The core must not branch on AI vendor identity. |

## Audit and drift

Read-only Route audit and sanitized desired-vs-observed drift are supported for the current topology/drivers. Current categories include PPM service/configuration, firewall/network, WireGuard, Hysteria2 listener/certificate, egress, stale ClientTarget render, and undetermined state.

Drift is evidence only. Automatic self-healing is not supported.

## Recovery

Encrypted local recovery of current schema-1 canonical state is supported. Recovery verifies archive integrity/path safety, relocates private SSH material, validates restored state, resets observed evidence, and performs no remote mutation by itself.

## Host and remote ownership boundary

PPM owns its named services, runtime identity, WireGuard interfaces, generated files, and individually named policy files. The initial setup also changes host-wide UFW defaults, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state. This is why the supported host must be dedicated and rebuildable.

Unrelated Xray/Hysteria/WireGuard installations or other host software are outside PPM ownership and must not be deleted, disabled, or treated as drift merely for existing. Uninstall does not restore unknown prior host-wide settings.

## Optional Cloudflare delivery

The Cloudflare Worker is supported only as a narrow private subscription-delivery endpoint. It is not a hosted PPM control plane, proxy data plane, user database, analytics service, or infrastructure source of truth.

## Compatibility rule

External software documentation does not make a capability supported. A capability is supported only when PPM has a deterministic driver/renderer or bounded adapter, machine-readable capability truth, preflight semantics, and tests for the claimed boundary.
