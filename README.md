# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Use AI to manage networking on your own servers.**

Route Steward helps you deploy, check, migrate, and recover network connections on servers you manage. You provide the servers, accounts, and authorization; Route Steward gives a capable AI agent a repeatable, validated way to operate them from your local computer.

![Synthetic Route Steward diagram separating the AI-operated control plane from direct and optional WireGuard relay traffic paths through Entry-A and Relay-A.](docs/assets/network-path-lifecycle.svg)

## Start with an AI agent

Paste this prompt into Codex or another agent that can read files and run PowerShell:

```text
Open https://github.com/squarepots/route-steward and help me manage networking on my own servers. Clone it if needed, read AGENTS.md and the repository Skill, inspect capabilities, and run quick local validation. Before asking for infrastructure details, explain the dedicated-host requirements, host-wide effects, and operating boundary. Keep sensitive state private, run preflight before changes, and return sanitized results.
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## What you need

- a local computer with PowerShell 7 and a tool-capable AI agent;
- one or two dedicated, rebuildable Ubuntu 24.04 amd64 servers;
- authorized SSH access with a Unix username and private-key path;
- Mihomo/Clash Verge-compatible software or Shadowrocket.

Route Steward prepares the whole server, so each managed host must be dedicated to this networking setup.

## What Route Steward does

It creates validated server and client configuration, checks the live setup, helps replace infrastructure without discarding the working connection first, and produces encrypted recovery archives.

[Compatibility](docs/COMPATIBILITY.md) lists the exact hosts, protocols, clients, topology, and optional Cloudflare delivery currently supported.

## Host effects and privacy

Setup changes host-wide firewall, swap, SSH, system, logging, update, and monitoring settings. Sensitive state and generated files stay in the selected local private directory; every change requires a ready preflight. Read [Operations](OPERATIONS.md), [Privacy](docs/PRIVACY.md), and [Security](SECURITY.md) before deployment.

Use only servers, accounts, and network resources you own or are authorized to administer. The full policy is in [Operating boundary](docs/OPERATING-BOUNDARY.md).

Route Steward is licensed under [AGPL-3.0-only](LICENSE). The vendored QR generator retains its MIT attribution in [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
