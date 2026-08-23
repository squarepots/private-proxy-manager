# Quickstart

This is a short orientation for a first local setup. PPM is operated through a capable local-file/tool agent; the commands below are validation and inspection aids, not a second end-user interface.

## Requirements

- a rebuildable, dedicated Ubuntu 24.04 amd64 VPS;
- SSH access with a valid Unix username and key;
- a local PowerShell 7 runtime for the PPM machine surface;
- a supported Mihomo/Clash-compatible client or Shadowrocket if you want rendered client output;
- Node.js and Wrangler only when using the optional subscription Worker;
- 7-Zip only when creating or restoring encrypted recovery archives.

Read the [host effects](../README.md#before-you-start-host-effects) before connecting a server. Do not use a shared production host.

## Let the agent inspect first

Ask your local tool-capable agent:

> Inspect PPM capabilities and current private state. I want a direct or single-hop relay route on my dedicated Ubuntu 24.04 amd64 host. Explain missing context, host-wide effects, and authorization before making any mutation.

The agent should use the canonical `agent/ppm-agent.ps1` surface, bootstrap only when private state is absent, and refuse a mutation until scoped preflight reports `ready=true`.

## The normal sequence

```text
capabilities → bootstrap (if needed) → context/drift
→ gather server/client facts → create desired objects
→ preflight → execute → audit/render → explain result
```

Use stable non-identifying IDs such as `entry-a`, `route-a`, and `mobile-a`. Do not use a city, employer, customer, home network, or other private context as an ID.

## What success looks like

The result should identify the supported server contract, the selected Route and ClientTarget, the audit status, and private-root-relative artifact names such as `<private>/delivery/mobile.html`. It must not return a Windows drive path, SSH key contents, subscription token, Provider URL, or raw remote diagnostics.

## If something is wrong

Stop at the typed drift or preflight result. Drift is evidence, not permission for automatic repair. Ask the agent to diagnose the named category and propose the smallest supported operation. Migration keeps the old route available until replacement access and rendering are verified.

For recovery, restore into a clean private directory, use the repository recovery workflow, and treat the archive plus its password as a single sensitive bundle. See [Operations](../OPERATIONS.md), [Security](../SECURITY.md), and [FAQ](FAQ.md).
