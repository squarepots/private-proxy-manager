# Quickstart

PPM is designed for an AI agent that can open a repository, read local files, and run PowerShell. You describe the route you want; the agent discovers the supported workflow and uses PPM's deterministic operations.

## 1. Give the repository to an agent

Paste this into Codex or another tool-capable agent:

> Open https://github.com/squarepots/private-proxy-manager and help me create my first private proxy route. Clone it if needed. Read AGENTS.md and .agents/skills/private-proxy-manager/SKILL.md. Run capability discovery and the quick local validation before using any real infrastructure. Explain the prerequisites and host-wide effects, collect only the required facts, keep all private state under the ignored private directory, and do not execute a mutation until preflight is ready.

The agent should run:

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

These commands inspect the repository and validate the local machine surface. They do not deploy a server.

## 2. Prepare the required inputs

For the first route, prepare:

- a dedicated, rebuildable Ubuntu 24.04 amd64 VPS;
- its public address;
- a valid Unix SSH username and local private-key path;
- the client you want to configure: Mihomo/Clash Verge-compatible software or Shadowrocket;
- your desired direct or single-hop relay topology.

Use non-identifying IDs such as `entry-a`, `route-a`, and `desktop-a`. Keep cities, employers, customers, and home-network names out of IDs.

Before accepting server details, the agent should explain the host effects in the [README](../README.md#host-effects).

## 3. Let PPM build the plan

The normal machine workflow is:

```text
capabilities → bootstrap when absent → context and drift
→ gather required facts → create desired objects
→ preflight → execute → audit and render
```

Bootstrap creates neutral schema-1 state. It does not select a region, Provider, policy, Profile, client, subscription, or AI vendor.

Preflight returns the exact missing context, conflicts, expected effects, and authorization class. The agent continues only when `ready=true`.

## 4. Check the result

A successful result identifies:

- the Server and Route created;
- the supported host/topology contract;
- the remote audit status;
- the ClientTarget and private-root-relative artifact, for example `<private>/delivery/desktop-a.yaml`;
- any remaining drift or user decision.

The result must not contain an absolute home path, key contents, Provider URL, subscription token, live node URI, or raw SSH output.

## 5. Continue safely

Ask the agent to use read-only audit and drift before changing an existing route. For replacement, PPM creates and validates new capacity while the current route remains available. For backup and recovery, use the repository-owned 7-Zip prompt and never put the archive password in chat or command arguments.

Read [Operations](../OPERATIONS.md) for machine semantics, [Compatibility](COMPATIBILITY.md) for implemented support, [Security](../SECURITY.md) for authority and secret handling, and the [FAQ](FAQ.md) for plain-language answers.
