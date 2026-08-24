# Quickstart

Route Steward helps an AI agent set up and manage a private proxy on VPS servers you control. The normal interface is one native executable for Linux, macOS, and Windows.

## 1. Install the executable

Download the archive for your operating system and architecture from [GitHub Releases](https://github.com/squarepots/route-steward/releases), verify it against `SHA256SUMS`, and place `route-steward` (or `route-steward.exe`) on your `PATH`.

Developers can install from source with Go 1.27:

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

Normal use does not require PowerShell or Node.js. Node.js is needed only for the optional Cloudflare Worker subscription publisher.

## 2. Give the repository to an agent

Paste this into Codex or another agent that can read files and run local commands:

```text
Open https://github.com/squarepots/route-steward and help me set up and manage a private proxy on my own servers. Clone it if needed, read AGENTS.md and .agents/skills/route-steward/SKILL.md, then use the release binary or build the Go CLI. Run capabilities before asking for infrastructure details. Explain the dedicated-host requirements and host effects, keep operational state private, run preflight before every change, and return sanitized results.
```

The agent should begin with:

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
route-steward drift --private-dir ./private
```

For a source checkout, the same interface is available as `go run ./cmd/route-steward <command>`.

## 3. Prepare the first proxy

The agent will ask for the facts declared by capability discovery:

- one dedicated, rebuildable Ubuntu 24.04 amd64 VPS for a direct route, or two for a relay;
- each server's public address, valid Unix SSH username, and local private-key path;
- the desired direct or single-hop relay connection;
- a Mihomo/Clash Verge-compatible or Shadowrocket client target.

Use non-identifying IDs such as `entry-a`, `route-a`, and `desktop-a`. Route Steward stores real operational values only in the selected private directory.

## 4. Let the agent operate the workflow

```text
capabilities → bootstrap when absent → context and drift
→ create desired Server / Link / Route / Profile / ClientTarget objects
→ preflight → execute → audit → render
```

Preflight returns missing facts, conflicts, expected effects, and authorization class. Execution continues only when `ready=true`. A deployed route with unexpected or undetermined live state is not blindly overwritten.

## 5. Check the outcome

A successful response identifies the proxy route, server audit result, and private-root-relative client artifact. Server audit proves that the managed configuration and services match; it is not yet an end-to-end client traffic test.

```json
{
  "route": "route-a",
  "state": "deployed",
  "audit": { "status": "in-sync" },
  "artifact": { "relative_path": "<private>/delivery/desktop-a.yaml" }
}
```

Returned data omits credentials, absolute home paths, Provider URLs, subscription tokens, live node URIs, and raw SSH output.

## 6. Continue or recover

Ask the agent to run audit and drift before changing an existing route. The current `migrate-route` capability supplies an overlap-first sequence; the agent must carry out and confirm its stages while preserving old capacity. Encrypted recovery uses `route-steward backup` and `route-steward recover`; enter the password only in the local 7-Zip prompt.

Read [Compatibility](COMPATIBILITY.md), [Operations](../OPERATIONS.md), [Privacy](PRIVACY.md), [Security](../SECURITY.md), and the [operating boundary](OPERATING-BOUNDARY.md) before real deployment.
