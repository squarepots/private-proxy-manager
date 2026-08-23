# Private Proxy Manager

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager (PPM) helps an AI agent build and maintain private proxy routes on servers you control. It keeps the desired network plan and credentials in a private local directory, deploys the supported server stack over SSH, creates client configurations, audits the live routes, and guides server replacement without taking the working route down first.

You provide the servers, SSH access, and a supported proxy client. PPM provides the repeatable operating layer between them.

## Start with an AI agent

Give this repository URL to Codex or another agent that can read local files and run PowerShell, then use this prompt:

> Open <https://github.com/squarepots/private-proxy-manager> and operate PPM for me. If it is not local, clone it first. Read AGENTS.md and the repository Skill before acting. Inspect the capability surface and run the quick local validation. Then explain what I need for my first route and the host-wide effects before asking for any real server details. Keep credentials and generated client files in the ignored private directory, run preflight before every change, and show me only sanitized results.

The agent's first safe checks are:

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

Capability discovery is the machine-readable source of truth. The repository Skill tells the agent how to gather context, bootstrap neutral local state, create the needed objects, validate each change, and report the result without exposing secrets.

## What you need

- a local computer with a tool-capable AI agent and PowerShell 7;
- one or two dedicated, rebuildable Ubuntu 24.04 amd64 VPS hosts;
- SSH access with a valid Unix username and private-key path;
- Mihomo/Clash Verge-compatible software or Shadowrocket for client use.

Node.js and Wrangler are needed only for optional private Cloudflare subscription delivery. 7-Zip is needed only for encrypted backup and recovery.

PPM prepares the whole server, so use a dedicated host rather than one shared with an existing production workload.

## What PPM does for you

- builds a direct Hysteria2 route or a single-hop WireGuard relay route;
- keeps server, route, provider, profile, and client-target intent in one validated local inventory;
- generates Mihomo/Clash-compatible files and Shadowrocket imports;
- optionally publishes one private Shadowrocket subscription per isolated ClientTarget;
- compares desired state with bounded remote evidence and reports typed drift;
- replaces infrastructure overlap-first, keeping existing capacity available until the replacement is proven;
- creates encrypted recovery archives that do not depend on chat history.

A clean bootstrap starts with no geography, provider, policy, client, subscription, or AI-vendor assumption. The agent asks only for facts required by the route you actually want.

## Host effects

Initial deployment prepares a dedicated Ubuntu host and may:

- install `ufw`, `unattended-upgrades`, `vnstat`, `mtr`, `curl`, `jq`, `openssl`, and related packages;
- create a 1 GiB `/swapfile` and persist it in `/etc/fstab`;
- set and enable UFW defaults, protect SSH, and block outbound SMTP ports 25, 465, and 587;
- install PPM-named SSH, sysctl, BBR, journald, unattended-upgrades, and module configuration;
- create PPM services, runtime users, WireGuard interfaces, configuration, and credentials.

Uninstall removes PPM-owned services, interfaces, files, and named policy files. It leaves packages, swap, and unknown previous host-wide settings in place because reconstructing an earlier host configuration would be unsafe. See [Operations](OPERATIONS.md) for the exact ownership boundary.

## What a successful result looks like

```text
route               direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

This is a synthetic shape. Agent and MCP results return private-root-relative artifact identities rather than Windows drive paths, home directories, SSH keys, provider URLs, tokens, or raw remote diagnostics.

## Supported stack

The current tested stack is:

- Ubuntu 24.04 amd64 dedicated hosts accessed through BYO SSH;
- Hysteria2 ingress;
- direct and single-hop WireGuard relay topology;
- optional generic Mihomo HTTP Providers;
- Mihomo/Clash Verge-compatible and Shadowrocket rendering;
- optional ClientTarget-scoped Cloudflare Worker delivery.

See [Compatibility](docs/COMPATIBILITY.md) for the complete capability contract. If a protocol, host, renderer, or provider type is absent there and absent from capability discovery, PPM does not implement it.

## Privacy and authority

PPM's deterministic engine does not upload private state, but a cloud AI runtime may receive operation arguments such as a server address, SSH username, key path, and selected IDs. Use non-identifying IDs and choose an offline runtime when those arguments must remain on your machine.

Private inventory, credentials, generated client files, observed evidence, and recovery archives are local sensitive data. Protect the private directory with operating-system permissions and backups, and never paste its contents into issues or chat.

Every mutation is checked by local preflight. Missing or conflicting context blocks execution. Subscription-token rotation requires explicit current approval, remote changes stay inside PPM's ownership boundary, and infrastructure migration is overlap-first. Network privacy limits and compromise responses are documented in [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), and the [Threat model](docs/THREAT-MODEL.md).

## Learn more

- [Quickstart](docs/QUICKSTART.md): hand the URL to an agent and complete the first safe workflow.
- [FAQ](docs/FAQ.md): plain-language answers about hosts, AI visibility, recovery, drift, and clients.
- [Architecture](ARCHITECTURE.md): object model and deterministic boundaries.
- [Contributing](CONTRIBUTING.md): development and validation contract.
- [Releasing](docs/RELEASING.md): version and release process.

PPM is licensed under [AGPL-3.0-only](LICENSE). The vendored QR generator retains its MIT attribution in [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
