# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Tell your AI how your network path should run. Route Steward keeps it working.**

Route Steward is a local-first lifecycle manager for self-hosted network paths. A capable AI agent turns your intended connectivity across operator-controlled infrastructure into validated state, server deployment, client configuration, live audit, drift detection, migration, and recovery.

Route Steward assumes Internet reachability between the endpoints you select. The Internet provides transport; you provide the servers, accounts, and authority to use the network resources; Route Steward provides the repeatable operating layer.

## Start with an AI agent

Give this repository URL to Codex or another agent that can read local files and run PowerShell, then use this prompt:

> Open <https://github.com/squarepots/route-steward> and operate Route Steward for me. Clone it when needed, read AGENTS.md and the repository Skill, inspect the capability surface, and run quick local validation. Explain the requirements and host-wide effects for my first self-hosted network path, gather the required context, keep credentials and generated client files in the private directory, run preflight before each change, and return sanitized results.

The agent begins with:

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

Capability discovery is the machine-readable source of truth. The repository Skill guides context gathering, neutral bootstrap, scoped execution, validation, and sanitized reporting.

## What you provide

- a local computer with PowerShell 7 and a tool-capable AI agent;
- one or two dedicated, rebuildable Ubuntu 24.04 amd64 servers;
- authorized SSH access with a Unix username and private-key path;
- Mihomo/Clash Verge-compatible software or Shadowrocket for client use.

Node.js and Wrangler support optional private configuration delivery through Cloudflare. 7-Zip supports encrypted backup and recovery.

Route Steward prepares the whole server, so each managed host should be dedicated to this network path.

## What Route Steward manages

- direct Hysteria2 paths and single-hop WireGuard relay paths;
- validated desired state for Servers, Links, Routes, Providers, Profiles, and ClientTargets;
- Mihomo/Clash-compatible files and Shadowrocket imports;
- optional isolated configuration delivery for each Shadowrocket ClientTarget;
- bounded remote evidence and typed desired-versus-observed drift;
- overlap-first infrastructure replacement with proven capacity before cutover;
- encrypted recovery archives independent of chat history.

A clean bootstrap begins with neutral state. The agent adds geography, providers, policy, clients, delivery, and infrastructure only from the context required for your goal.

## Operating boundary

Route Steward is designed for servers, accounts, and network resources that the operator owns or is authorized to administer. Each deployment follows the laws, carrier requirements, cloud-provider terms, and organizational policies applicable to its location and use case.

The open-source distribution uses a bring-your-own-infrastructure model. Network providers remain the source of connectivity, while Route Steward manages configuration and lifecycle on the selected infrastructure. See [Operating boundary](docs/OPERATING-BOUNDARY.md) for the complete project policy.

## Host effects

Initial deployment prepares a dedicated Ubuntu host and may:

- install `ufw`, `unattended-upgrades`, `vnstat`, `mtr`, `curl`, `jq`, `openssl`, and related packages;
- create a 1 GiB `/swapfile` and persist it in `/etc/fstab`;
- configure UFW defaults, SSH protection, and outbound SMTP controls;
- install Route Steward SSH, sysctl, BBR, journald, unattended-upgrades, and module policies;
- create Route Steward services, runtime users, WireGuard interfaces, configuration, and credentials.

The uninstall workflow removes Route Steward-managed services, interfaces, files, and named policy files. Packages, swap, and earlier host-wide settings remain available for operator review. See [Operations](OPERATIONS.md) for the exact ownership boundary.

## What a successful result looks like

```text
path                direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

This synthetic result uses private-root-relative artifact identities. Agent and MCP output keeps local paths, SSH material, provider URLs, delivery credentials, and raw diagnostics within their designated private surfaces.

## Supported stack

- Ubuntu 24.04 amd64 dedicated hosts accessed through BYO SSH;
- Hysteria2 ingress;
- direct and single-hop WireGuard relay topology;
- optional generic Mihomo HTTP Providers;
- Mihomo/Clash Verge-compatible and Shadowrocket rendering;
- optional ClientTarget-scoped Cloudflare Worker delivery.

[Compatibility](docs/COMPATIBILITY.md) is the human-readable capability contract; capability discovery is its runtime counterpart.

## Privacy and authority

The deterministic engine stores desired state, credentials, generated client files, observed evidence, and recovery archives in the selected local private directory. A cloud AI runtime may process the operation arguments required for a task, such as server addresses, SSH usernames, key paths, and selected IDs. Non-identifying IDs and an offline runtime provide a stronger local boundary when required.

Every mutation passes scoped preflight. Credential rotation uses explicit current approval, remote writes stay within Route Steward-managed resources, and infrastructure migration follows an overlap-first workflow. [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and the [Threat model](docs/THREAT-MODEL.md) describe these boundaries in detail.

## Learn more

- [Quickstart](docs/QUICKSTART.md): hand the URL to an agent and complete the first safe workflow.
- [FAQ](docs/FAQ.md): hosts, AI visibility, recovery, drift, and clients.
- [Architecture](ARCHITECTURE.md): object model and deterministic boundaries.
- [Contributing](CONTRIBUTING.md): development and validation contract.
- [Releasing](docs/RELEASING.md): version and release process.

Route Steward is licensed under [AGPL-3.0-only](LICENSE). The vendored QR generator retains its MIT attribution in [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
