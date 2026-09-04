# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**Set up and manage private proxies on your own servers with an AI agent.**

Give an AI agent this repository and describe the proxy you want. Route Steward supplies the commands, safety checks, server setup, client files, audits, and recovery workflow.

## Give the URL to an AI agent

Paste this into Codex or another agent that can read files and run local commands:

```text
Open https://github.com/squarepots/route-steward and help me set up and manage a private proxy on servers I control. Read AGENTS.md and .agents/skills/route-steward/SKILL.md, use the Route Steward release for this computer, and begin with route-steward capabilities.
```

See the [Quickstart](docs/QUICKSTART.md) for installation and prerequisites.

## What it gives you

- a private Hysteria2 proxy through one server or a two-server WireGuard relay;
- optional port hopping for networks that throttle or filter individual UDP ports;
- private client files for Mihomo/Clash Verge-compatible apps, Karing, Shadowrocket, and headless Hysteria2;
- server audits, configuration drift reports, and real on-demand traffic checks;
- resumable server replacement that tests the new path before switching clients;
- encrypted local backups and recovery;
- JSON commands through the CLI or local stdio MCP.

The current server baseline is a dedicated, rebuildable Ubuntu 24.04 amd64 VPS with authorized SSH key access. Exact protocols, clients, topology, and optional delivery are listed in [Compatibility](docs/COMPATIBILITY.md).

## Host effects and privacy

Initial setup changes firewall, swap, SSH, sysctl, logging, updates, packages, and monitoring across the host. Use a dedicated, rebuildable server.

Keys, operational state, generated client files, and recovery archives stay in the private directory you select and are excluded from Git. A cloud AI service may still receive the server details needed for an operation; use an offline runtime when those details must remain local.

Use only servers, accounts, and network resources you own or are authorized to administer. Read [Operations](OPERATIONS.md), [Privacy](docs/PRIVACY.md), and [Security](SECURITY.md) before deployment.

Route Steward is [AGPL-3.0-only](LICENSE). The vendored QR generator retains its MIT attribution in [client/vendor/NOTICE.md](client/vendor/NOTICE.md).
