# Route Steward agent contract

Route Steward (RST) is agent-native lifecycle software for self-hosted network paths. A user should be able to give a capable agent this repository URL, describe the path they want across operator-controlled infrastructure, and let the agent discover the supported workflow.

## First actions

1. Read `.agents/skills/route-steward/SKILL.md`.
2. Run `route-steward capabilities` before assuming support. In a source checkout, use `go run ./cmd/route-steward capabilities`.
3. Run `go test ./...` before using a changed source checkout with real infrastructure.
4. Establish the operating boundary from `docs/OPERATING-BOUNDARY.md` for the selected infrastructure and network resources.
5. Bootstrap only when private state is absent.
6. Read sanitized context and drift before changing an existing setup.
7. Run scoped preflight before every mutation and execute only when `ready=true`.
8. Validate meaningful effects and report a sanitized result.

Runtime-specific instruction files must point here and to the repository Skill instead of duplicating the product contract.

## Machine and object model

The native `route-steward` executable is the canonical sanitized machine surface and includes the local stdio MCP server. Go owns state, preflight, rendering, deployment orchestration, drift, subscription, and recovery. Remote host changes remain in the embedded, audited `server/*.sh` payloads. `agent/route-steward-agent.ps1` is a compatibility forwarder for older callers.

Keep the schema-1 object boundaries explicit:

- Server: `compute.driver=byo-ssh`, Ubuntu 24.04 amd64, `host_ownership=dedicated`;
- Link: `driver=wireguard`, single hop;
- Route: `ingress.driver=hysteria2`, direct or relay;
- Provider: optional `source_type=mihomo-http`;
- Profile: reusable Route, Provider, and policy selection;
- ClientTarget: renderer and delivery identity referencing a Profile.

Clean bootstrap is neutral. Gather actual context before creating Profiles or ClientTargets.

## Private state and conversational output

Tracked files contain reusable source, tests, public documentation, release metadata, portable instructions, and synthetic examples only.

Real inventory, observed evidence, credentials, Provider/subscription URLs, SSH material, generated client artifacts, and recovery archives belong under ignored local `private/` or another explicitly selected private root. Inspect only what the current operation requires. Never copy private values into commits, issues, documentation, logs, or chat.

Use non-identifying IDs. Return sanitized machine results; artifact locations must remain private-root-relative.

## Execution and authority

The agent owns workflow orchestration, not the user's authority. Preflight must establish the exact target, required state and access, expected effects, conflicts, and authorization class.

Prefer repository-owned deterministic operations. Raw SSH is limited to read-only diagnosis when no bounded RST diagnostic exists; it must not become an alternate configuration system.

Drift is evidence. A deployed Route with drifted or undetermined state is not overwritten until the discrepancy is understood.

Subscription-token rotation is a target-scoped `credential-change` requiring explicit current approval. It changes only the selected ClientTarget credential.

Migration is overlap-first: create, deploy, audit, render, and prove replacement capacity while the working route remains available.

## Remote ownership

The supported host is dedicated and rebuildable because setup changes UFW, swap/fstab, SMTP egress, SSH/sysctl/journald, packages, unattended-upgrades, and vnstat.

Remote deployment and uninstall mutate RST-owned resources and named policy files. Existing networking software, WireGuard state, services, accounts, and host files remain outside RST ownership. Uninstall preserves prior global host settings that lack a reliable reconstruction source.

## Capability and documentation ownership

`docs/COMPATIBILITY.md` and capability discovery define implemented support. External software documentation may provide evidence but does not add a RST driver, renderer, or operation.

Document ownership:

- README and Quickstart: product value, prerequisites, URL-first agent onboarding, and host effects;
- Operating boundary: authorized infrastructure, Internet/provider context, and deployment conditions;
- Compatibility: implemented support;
- Operations: machine operations and remote ownership;
- Security: reporting, trust, secrets, preflight, and remote safety;
- Threat model: concrete compromise cases;
- Privacy: model and network visibility;
- repository Skill: operational behavior for agents.

## Git and release

Treat every tracked blob as public source. Preserve AGPL-3.0-only and vendored notices.

Before a PR is ready:

1. review the final diff and update from the target branch;
2. classify version impact as `none`, `patch`, `minor`, or `major`;
3. record the decision and reason in the PR body;
4. for a version change, run `scripts/Bump-Version.ps1` once from the current target-branch version;
5. run full local validation and let public hosted CI validate the same tree.

Follow `docs/RELEASING.md`. Git mutations and publication still require the active user's authorization.
