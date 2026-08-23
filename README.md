# Private Proxy Manager

[简体中文](README.zh-CN.md) · [Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager (PPM) is a local-first control layer for self-hosted Hysteria2 and WireGuard routes. It keeps desired state and credentials in a private local directory, deploys supported server components over SSH, renders client configurations, and reports when observed infrastructure or client artifacts drift from the plan.

PPM is not a VPN service, proxy client, hosted dashboard, or server marketplace. It prepares infrastructure and client artifacts; Mihomo/Clash-compatible clients and Shadowrocket carry traffic on your devices.

## Is PPM for you?

PPM is for a technical self-hoster who has, or is willing to prepare, a **dedicated, rebuildable Ubuntu 24.04 amd64 VPS** and SSH access. It is useful when manual proxy configuration is error-prone, more than one route or device must stay consistent, or a server needs to be replaced without immediately breaking a working route.

PPM is not intended for a shared production host, a consumer VPN subscription, a phone-only setup, automatic VPS purchasing, multi-user billing, traffic analytics, anonymity guarantees, or arbitrary protocols and clients.

## Before you start: host effects

The current server setup is intentionally a whole-host preparation step. Use a fresh dedicated host that you can rebuild. Deployment may:

- install packages including `ufw`, `unattended-upgrades`, `vnstat`, `mtr`, `curl`, `jq`, and `openssl`;
- create and persist a 1 GiB `/swapfile` in `/etc/fstab`;
- set UFW defaults, enable UFW, allow/limit SSH, and block outbound SMTP ports 25, 465, and 587;
- install SSH, sysctl, BBR, journald, unattended-upgrades, and module configuration under PPM-named files;
- create PPM services, runtime users, WireGuard interfaces, configuration, and generated credentials.

Uninstall removes PPM-owned files, services, interfaces, and named policy files. It deliberately does **not** restore assumed previous UFW defaults, remove the swapfile, undo package installation, or recover an unknown prior host configuration. Review [Operations](OPERATIONS.md) before using a host that contains anything else you need.

## A synthetic first conversation

Give a capable local-file/tool agent this request:

> Read the PPM repository and its capability surface. I want a direct route on my dedicated Ubuntu 24.04 amd64 host. First show me the required context and host-wide effects. Do not deploy until preflight is ready and I explicitly confirm any material decision. Keep secrets and generated client files in the selected private directory.

The agent should inspect capabilities, create neutral private state when needed, gather the missing server/client facts, run preflight, and explain expected effects. A clean bootstrap does not assume a region, Provider, Profile, client application, subscription, or model vendor.

The following is a synthetic shape of a successful result; it is not a real server or user configuration:

```text
desired route       direct / entry-a
server contract     byo-ssh / Ubuntu 24.04 amd64 / dedicated
client artifacts    Mihomo YAML, Shadowrocket offline import
remote audit        healthy
drift               none
private outputs     <private>/delivery/...
```

## What PPM manages

- Hysteria2 ingress with repository-pinned binaries and certificate material;
- direct Routes and single-hop WireGuard entry-to-exit relay Routes;
- bring-your-own dedicated Ubuntu servers over SSH;
- optional generic Mihomo HTTP Providers stored as local secrets;
- Mihomo/Clash-compatible and Shadowrocket ClientTargets;
- target-scoped private Cloudflare Worker subscription delivery;
- desired state, observed audit evidence, typed drift, overlap-first migration, and encrypted local recovery.

The core separates **Profile** (reusable Route/Provider/policy selection) from **ClientTarget** (renderer and delivery identity). Desired state is inventory schema `1`; product version in `version.txt` is a separate domain.

## Privacy and AI boundary

The deterministic PPM engine does not upload private state. The selected AI runtime may still receive prompts and tool arguments. Depending on the operation, those arguments can include a server IP, SSH username, local key path, and selected stable IDs. Agent output replaces internal absolute artifact paths with a private-root-relative shape such as `<private>/delivery/client.yaml`, but “local-first” does not mean “the model sees no metadata.” Use an offline model/runtime when that distinction matters.

Private inventory, credentials, Provider URLs, subscription tokens, generated client files, audit evidence, and recovery archives are plaintext/private local state unless you protect them with your operating system, backups, and recovery workflow. Never commit or paste them into issues. PPM does not promise anonymity or invisibility from ISPs, VPS providers, Cloudflare, or destination services.

See [docs/PRIVACY.md](docs/PRIVACY.md), [SECURITY.md](SECURITY.md), and [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md).

## Agent and operation model

PPM exposes one deterministic machine surface under `agent/`; `mcp/` is a thin local-stdio adapter over it. The agent owns workflow orchestration, not the user's authority. Supported mutations require scoped context and a ready preflight. Steward Mode can handle routine technical work but never silently authorizes purchases, destructive server retirement, credential rotation, unrelated account changes, or material cost/privacy choices.

Drift is evidence, not automatic repair authority. Migration is overlap-first: prepare and validate replacement capacity before separately authorized retirement of the old path.

## Support boundary

The exact tested support matrix is [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md). In brief, the supported baseline is Ubuntu 24.04 amd64 on a dedicated host, Hysteria2 ingress, WireGuard single-hop relay, Mihomo/Clash-compatible output, and Shadowrocket output. Multi-hop, ARM64, arbitrary Linux distributions, arbitrary renderers, automatic cloud provisioning, and a hosted PPM control plane are not supported.

## Try it and contribute

Start with [docs/QUICKSTART.md](docs/QUICKSTART.md) or [docs/QUICKSTART.zh-CN.md](docs/QUICKSTART.zh-CN.md). The [FAQ](docs/FAQ.md) explains common boundaries in plain language. `AGENTS.md`, the repository Skill, capability discovery, schemas, and the deterministic code are the canonical technical contract; runtime-specific instructions must not create a competing authority.

For repository validation, use `scripts/Validate-Local.ps1 -Quick` for the focused local loop. The full environment matrix runs in hosted CI after the source is public. See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/RELEASING.md](docs/RELEASING.md).

PPM is licensed under [AGPL-3.0-only](LICENSE). The vendored QR generator remains under its original MIT attribution; see [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
