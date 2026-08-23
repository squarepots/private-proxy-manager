# FAQ

## What problem does PPM solve?

PPM turns a set of SSH-accessible VPS hosts into a repeatable private proxy setup. It keeps the intended topology, credentials, client output, remote audit, drift, migration, and recovery workflow consistent so you do not have to maintain them as unrelated manual steps.

## What do I need before I start?

You need a local computer with PowerShell 7 and a tool-capable AI agent, a dedicated rebuildable Ubuntu 24.04 amd64 VPS with SSH key access, and either Mihomo/Clash Verge-compatible software or Shadowrocket. A relay route uses two VPS hosts.

## Why must the server be dedicated?

Initial setup prepares the whole host. It changes UFW defaults, swap/fstab, SSH, sysctl, journald, packages, unattended-upgrades, SMTP egress, and vnstat state. A fresh dedicated host makes those effects explicit and keeps unrelated production workloads outside the change boundary.

## Can I start by giving the GitHub link to an AI agent?

Yes. Use the prompt in the [Quickstart](QUICKSTART.md). A capable agent can clone the repository, read its instructions, inspect machine-readable capabilities, run local validation, explain prerequisites, and then gather the minimum context for your route.

## Will the AI model see my server details?

It may. Operation arguments can include a server address, SSH username, local key path, and selected IDs. PPM sanitizes returned results, but a cloud runtime can still process the inputs it needs. Use non-identifying IDs and an offline runtime when those inputs must remain local.

## How are private files protected?

Inventory, credentials, generated client files, observed evidence, and recovery archives stay in the selected local private directory and are excluded from Git. They are plaintext unless your operating system, disk, or backup layer encrypts them. Portable recovery archives are encrypted through a local 7-Zip password prompt.

## What happens when a route changes unexpectedly?

Read-only audit records bounded evidence and drift reports the category. PPM does not overwrite a drifted or undetermined deployed route until the discrepancy is understood and a supported operation passes preflight.

## How does server replacement avoid interruption?

Migration is overlap-first: create and deploy replacement capacity, audit it, update client output, confirm it works, and keep the current route available throughout that proof. Retirement of old external capacity is a later, separate action.

## Which hosts, topologies, and clients work?

See [Compatibility](COMPATIBILITY.md). The machine-readable capability response is the runtime source of truth. Support is limited to the items explicitly listed there and implemented by the repository.

## What does the optional subscription Worker do?

It delivers one private Shadowrocket ClientTarget configuration from an isolated Cloudflare Worker endpoint. The bearer token is target-scoped and the UTF-8 subscription body is limited to 5120 bytes. Cloudflare remains inside that delivery path's privacy boundary.
