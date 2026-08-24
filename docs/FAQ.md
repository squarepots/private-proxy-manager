# FAQ

## What does Route Steward do?

Route Steward helps an AI agent set up and manage a private proxy on VPS servers you control. It generates server configuration and private client-app output through a reviewable, preflighted workflow.

## What do I need before I start?

You need the Route Steward release binary on a Linux, macOS, or Windows computer with a tool-capable AI agent, a dedicated rebuildable Ubuntu 24.04 amd64 VPS with SSH key access, and either Mihomo/Clash Verge-compatible software or Shadowrocket. A relay route uses two VPS hosts. PowerShell and Node.js are not required for normal use.

## How do I install it?

Download the archive for your operating system and architecture from [GitHub Releases](https://github.com/squarepots/route-steward/releases), verify it with `SHA256SUMS`, and place the executable on your `PATH`. Developers can use `go install github.com/squarepots/route-steward/cmd/route-steward@latest` with Go 1.27.

## Why must the server be dedicated?

Initial setup prepares the whole host. It changes UFW defaults, swap/fstab, SSH, sysctl, journald, packages, unattended-upgrades, SMTP egress, and vnstat state. A fresh dedicated host makes those effects explicit and keeps unrelated production workloads outside the change boundary.

## Can I start by giving the GitHub link to an AI agent?

Yes. Use the prompt in the [Quickstart](QUICKSTART.md). A capable agent can clone the repository, read its instructions, obtain or build the executable, inspect machine-readable capabilities, explain prerequisites, and then gather the minimum context for your route.

## Will the AI model see my server details?

It may. Operation arguments can include a server address, SSH username, local key path, and selected IDs. RST sanitizes returned results, but a cloud runtime can still process the inputs it needs. Use non-identifying IDs and an offline runtime when those inputs must remain local.

## How are private files protected?

Inventory, credentials, generated client files, observed evidence, and recovery archives stay in the selected local private directory and are excluded from Git. They are plaintext unless your operating system, disk, or backup layer encrypts them. Portable recovery archives are encrypted through a local 7-Zip password prompt.

## What happens when a route changes unexpectedly?

Read-only audit records bounded evidence and drift reports the category. RST does not overwrite a drifted or undetermined deployed route until the discrepancy is understood and a supported operation passes preflight.

## Does audit prove that the proxy carries Internet traffic?

No. Audit checks supported server configuration, services, listeners, relay state, and server-side exit evidence. The separate `health` operation runs a real pinned Hysteria2 client, makes Internet and hostname requests through the Route, compares the observed public exit with desired state, and reports IPv4/IPv6 where declared. Treat configuration audit and end-to-end connection health as separate results.

## Does health expose my public IP or run monitoring continuously?

No. Health is an on-demand check, not a monitoring service. It contacts ipify's address endpoints and Cloudflare's trace endpoint through the proxy and stores only bounded local evidence. The normal agent result reports whether the observed exit matches; exact public IP values are returned only when explicitly requested. Packet loss is reported as unsupported because RST does not yet have a stable, safe end-to-end metric for it.

## How does server replacement avoid interruption?

`migrate-route` persists an overlap-first transaction. It creates or reuses replacement capacity, deploys it without touching current client output, requires a healthy real Hysteria2 traffic check, and only then switches and validates affected ClientTargets. A failed deployment, health check, render, or subscription publication returns `workflow-blocked`; retrying the same migration resumes deterministically. Old remote capacity is never retired automatically and remains a later explicit destructive action.

## Which hosts, topologies, and clients work?

See [Compatibility](COMPATIBILITY.md). The machine-readable capability response is the runtime source of truth. Support is limited to the items explicitly listed there and implemented by the repository.

## What does the optional subscription Worker do?

It delivers one private Shadowrocket ClientTarget configuration from an isolated Cloudflare Worker endpoint. The bearer token is target-scoped and the UTF-8 configuration body is limited to 5120 bytes. Cloudflare remains inside that delivery path's privacy boundary.

## What operating conditions apply?

Each deployment uses servers, accounts, and network resources owned by the operator or administered with the resource owner's authorization. Applicable laws, carrier requirements, provider terms, and organizational policies shape the selected topology. See [Operating boundary](OPERATING-BOUNDARY.md).
