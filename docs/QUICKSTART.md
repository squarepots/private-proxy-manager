# Quickstart

Route Steward helps an AI agent deploy, check, migrate, and recover networking on servers you manage. Give the repository to an agent that can read local files and run PowerShell, then describe the connection you want.

## 1. Give the repository to an agent

Paste this into Codex or another tool-capable agent:

```text
Open https://github.com/squarepots/route-steward and help me manage networking on my own servers. Clone it if needed. Read AGENTS.md and .agents/skills/route-steward/SKILL.md. Run capability discovery and quick local validation before using real infrastructure. Explain the dedicated-host requirements, host-wide effects, and operating boundary, collect the required facts, keep sensitive state under the ignored private directory, and make changes only after preflight reports ready=true.
```

The agent should run:

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

These commands inspect the repository and validate the local machine surface. Server deployment begins later through a scoped, ready preflight.

## 2. Prepare the required inputs

For the first route, prepare:

- a dedicated, rebuildable Ubuntu 24.04 amd64 VPS;
- its public address;
- a valid Unix SSH username and local private-key path;
- the client you want to configure: Mihomo/Clash Verge-compatible software or Shadowrocket;
- your desired direct or single-hop relay topology.

Use non-identifying IDs such as `entry-a`, `route-a`, and `desktop-a`.

Before accepting server details, the agent should explain the [host effects and privacy boundary](../README.md#host-effects-and-privacy).

## 3. Let RST build the plan

The normal machine workflow is:

```text
capabilities → bootstrap when absent → context and drift
→ gather required facts → create desired objects
→ preflight → execute → audit and render
```

Bootstrap creates neutral schema-1 state. Region, Provider, policy, Profile, client, delivery, and AI-vendor choices enter state only from established context.

Preflight returns the exact missing context, conflicts, expected effects, and authorization class. The agent continues only when `ready=true`.

## 4. Check the result

A successful result identifies:

- the Server and Route created;
- the supported host/topology contract;
- the remote audit status;
- the ClientTarget and private-root-relative artifact, for example `<private>/delivery/desktop-a.yaml`;
- any remaining drift or user decision.

The sanitized result uses private-root-relative artifacts and keeps absolute home paths, key contents, Provider URLs, delivery tokens, live node URIs, and raw SSH output within their designated private surfaces.

## 5. Continue safely

Ask the agent to use read-only audit and drift before changing an existing route. For replacement, RST creates and validates new capacity while the current route remains available. For backup and recovery, enter the archive password only through the repository-owned local 7-Zip prompt.

Read [Operating boundary](OPERATING-BOUNDARY.md) for deployment conditions, [Operations](../OPERATIONS.md) for machine semantics, [Compatibility](COMPATIBILITY.md) for implemented support, [Security](../SECURITY.md) for authority and secret handling, and the [FAQ](FAQ.md) for plain-language answers.
