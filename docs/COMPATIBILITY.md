# Compatibility

This page lists the capability set implemented and tested by the current release. The machine-readable response from `agent/route-steward-agent.ps1 capabilities` is the runtime source of truth. Anything absent from both surfaces is outside the current support contract.

## Host and compute

| Capability | Supported contract |
| --- | --- |
| Compute | Bring-your-own server over SSH |
| Operating system | Ubuntu 24.04 |
| Architecture | amd64 |
| Ownership | Dedicated, rebuildable host with `compute.host_ownership=dedicated` |
| SSH identity | Valid Unix username and local private-key path |

Initial setup changes host-wide UFW, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state. Uninstall removes RST-owned resources and named policy files; it leaves unknown prior global settings, installed packages, and swap in place.

## Network topology

| Capability | Supported contract |
| --- | --- |
| Ingress | Hysteria2, exact version and SHA-256 pinned in deployment code |
| Direct Route | Client → Hysteria2 Server → declared exit |
| Relay Route | Client → Hysteria2 entry → one WireGuard Link → exit/NAT |
| Link | Single-hop WireGuard over an isolated RST interface/port/subnet |
| Address families | Hysteria2 client ingress supports IPv4 and IPv6; the relay Link uses IPv4 |

## Desired state

Inventory schema `1` is the persisted desired-state contract:

- Server with `compute.driver=byo-ssh`;
- Link with `driver=wireguard`;
- Route with `ingress.driver=hysteria2`;
- optional Provider with `source_type=mihomo-http`;
- Profile for reusable Route, Provider, and policy selection;
- ClientTarget for renderer and delivery identity.

Product SemVer in `version.txt` is independent from inventory schema compatibility. Recovery accepts schema 1 and resets disposable observed evidence.

Clean bootstrap creates a valid neutral inventory, empty secret index, and empty observed state. It waits for actual user context before creating Profiles or ClientTargets.

## Clients and rendering

| Capability | Supported contract |
| --- | --- |
| Mihomo | Private YAML output for Mihomo/Clash Verge-compatible clients |
| Shadowrocket offline | Private node-import HTML generated without external page resources |
| Shadowrocket subscription | Optional isolated Cloudflare Worker delivery for one ClientTarget |
| Default policy | Generic privacy DNS/routing behavior |
| `balanced-cn` policy | Explicit opt-in only |

A ClientTarget selects the renderer and delivery. Its referenced Profile selects Routes, optional Providers, and policy.

## Providers

The optional `mihomo-http` Provider accepts an HTTP or HTTPS source URL stored in local secret storage. RST remains fully usable with zero Providers.

## Agent interfaces

| Interface | Supported contract |
| --- | --- |
| Repository Skill | Canonical model-neutral operating instructions |
| `agent/route-steward-agent.ps1` | Canonical sanitized JSON machine surface |
| Local stdio MCP | Thin adapter over the same machine surface |
| AI runtime | Any capable runtime that can read the repository and invoke the local machine surface without changing core behavior |

## Audit, drift, migration, and recovery

Read-only Route audit and sanitized desired-versus-observed drift cover RST service/configuration, firewall/network, WireGuard, Hysteria2 listener/certificate, egress, ClientTarget render, and undetermined state.

Migration uses an overlap-first workflow composed from add, deploy, audit, and render operations. Encrypted recovery verifies the archive manifest and path safety, relocates SSH material, validates schema-1 state, resets observed evidence, and performs no remote mutation by itself.

## Optional Cloudflare delivery

The Worker delivers a token-protected Shadowrocket subscription body for one isolated ClientTarget. The body is checked as UTF-8 and must be no larger than 5120 bytes. Subscription-token rotation is target-scoped, requires explicit current approval, and leaves Route and other ClientTarget credentials unchanged.
