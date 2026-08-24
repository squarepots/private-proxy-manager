# Operations

This document describes RST's **internal machine-operation contract for agents and contributors**. It is not end-user onboarding. Normal users describe intent in conversation; the active AI agent owns discovery, context gathering, preflight, execution, validation, and explanation.

## Canonical machine surface

The native `route-steward` executable is the stable local machine interface. It emits sanitized JSON envelopes and operates against the selected private instance root (`--private-dir`, defaulting to ignored local `private/`). `route-steward mcp` exposes the same Go engine over local stdio; it does not duplicate state, business logic, renderers, or authorization.

The normal sequence is:

```text
capabilities
  ↓
bootstrap (only when private state is absent)
  ↓
context + drift
  ↓
gather missing local/external facts
  ↓
create the actual desired objects needed by the user
  ↓
preflight(operation, target, context)
  ↓
ready=false → gather/ask/stop
ready=true  → execute
  ↓
audit/validate meaningful effects
```

Do not skip preflight for a mutation merely because the agent believes the answer is obvious. Private operation context should use stdin where the host can do so, avoiding sensitive infrastructure values in process command lines.

## Agent result envelope

Machine responses use a stable top-level shape:

```json
{
  "schema_version": 1,
  "command": "preflight",
  "success": true,
  "code": "ok",
  "data": {}
}
```

`success=false` means the requested machine action did not complete. A blocked mutation is not an invitation to bypass the gate; inspect `missing_context`, `conflicts`, authorization information, and expected effects.

The machine surface intentionally suppresses raw secret-bearing lower-level diagnostics.

## Private state

```text
<private>/inventory.json    canonical desired Server / Link / Route / Provider / Profile / ClientTarget state
<private>/secrets/          canonical credentials, Provider URLs, subscription state, payloads
<private>/observed.json     disposable sanitized remote audit evidence
<private>/migrations.json   resumable overlap-first migration checkpoints
<private>/delivery/         generated ClientTarget artifacts + hash-only render manifest
<private>/recovery/         encrypted recovery artifacts
<private>/tools/            verified disposable runtime helper cache
<private>/health/           ephemeral secret-bearing health probe configuration
```

Agents should prefer sanitized `context`/`drift` results. Read raw private state only when a supported operation genuinely requires it and never echo secret values into conversation.

## State contract

Inventory schema `1` is the current persisted desired-state compatibility boundary.

- **Server** declares `compute.driver=byo-ssh`.
- **Link** declares `driver=wireguard`.
- **Route** declares `ingress.driver=hysteria2`.
- **Provider** declares `source_type=mihomo-http` and a local `source_secret_ref`.
- **Profile** selects Routes, optional Providers, and policy.
- **ClientTarget** references a Profile and owns renderer/delivery identity.

RST does not publish conversion logic for development-only schemas that were never public. Recovery accepts the current public desired-state schema only. There is no independent persisted `model_version` axis.

## Capability discovery

Do not hard-code assumptions from this document into runtime adapters. Ask the machine surface for capabilities and driver truth.

Initial operation families include:

- local read: status/context/drift;
- remote read: supported Route audit and on-demand end-to-end health;
- local desired-state writes: Server/Link/Route/Provider/Profile/ClientTarget lifecycle;
- local private output: render ClientTarget, backup;
- remote RST write: deploy Route;
- external configuration publication: private subscription publication;
- guarded target-scoped credential change: subscription-token rotation;
- workflow-level migration/recovery.

`route-steward migrations --private-dir <directory>` returns only sanitized checkpoint summaries. Use it after an agent or local process restart to discover the recorded replacement identity and next action without reading raw private state.

Capability metadata is the source of truth when this document and code differ.

## Bootstrap

Clean bootstrap creates valid schema-1 local state with:

- no Server, Link, Route, or Provider assumptions;
- an available policy catalog but no selected policy/Profile;
- no ClientTarget, device, application, or subscription assumption;
- empty secret index and observed state;
- private delivery/recovery directories under the selected private root.

The agent gathers actual user context and then explicitly creates the required Profile and ClientTarget objects.

Bootstrap is idempotent when complete state already exists and **fails closed on partial initialization** rather than overwriting or guessing a repair.

## Structured desired-state operations

Agent-native creation operations are non-interactive.

### Server

The agent gathers stable server identity, public network facts, SSH user/key reference, and any known region/provider metadata. Adding the Server updates local desired state only; it does not connect to the server.

### Link

A new WireGuard Link references existing entry/exit Servers, allocates collision-free RST-native interface/port/subnet resources, and generates canonical key material locally. Adding it does not deploy remotely.

### Route

A new direct or relay Route references existing topology, allocates a listener when needed, generates canonical Hysteria2 credentials/certificate/payload locally, and starts `pending` / disabled. It becomes enabled only after deterministic deployment succeeds.

### Provider

A generic Provider is optional. Its URL is stored only in local secret storage. Provider update is transactional and removal is blocked while a Profile references it.

### Profile / ClientTarget

Profile lifecycle changes reusable selection only. A new Profile does not silently select a geography-specific policy. ClientTarget lifecycle changes concrete renderer/delivery identity. Removing a Profile is blocked while a ClientTarget references it. Removing a subscription-backed ClientTarget is blocked until its external subscription state has been explicitly retired/revoked.

## Deployment ownership

A Route deployment uses repository-owned deployment internals through the execution library. Agent-facing execution captures lower-level output so the machine protocol remains clean.

RST owns its `/usr/local/lib/route-steward`, `/etc/route-steward`, `/var/lib/route-steward`, `route-steward-*` systemd units, `route-steward-hysteria` runtime user, `wg-rst*` Link interfaces, generated files, and individually named policy files. The initial host preparation also changes global UFW defaults, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state.

Use only a dedicated, rebuildable Ubuntu 24.04 amd64 host. Deployment/uninstall must not delete, disable, overwrite, or require the absence of unrelated Xray/Hysteria/WireGuard software. Uninstall removes RST-owned artifacts and named policy files but does not restore unknown prior UFW defaults, swap/fstab, packages, or global host behavior.

An already-deployed Route is read-only audited before overwrite. If the current remote state is drifted or undetermined, deployment refuses to overwrite it until the discrepancy is understood.

After ordinary deployment, the agent performs read-only audit, updates sanitized observed evidence, and records current ClientTarget render hashes. A migration deliberately suppresses deployment-time rendering until the replacement passes end-to-end health.

## Audit and drift

Remote audit emits only bounded typed evidence into the deterministic core. Agent/MCP output never receives raw SSH/server diagnostics.

Supported drift categories include `service-missing`, `remote-config-mismatch`, `firewall-network-mismatch`, `wireguard-link-mismatch`, `hysteria-listener-mismatch`, `certificate-mismatch`, `egress-mismatch`, `client-render-stale`, `undetermined`, and in-sync/disabled/never-audited informational states.

Observed evidence is disposable. Drift does not self-heal; repair requires its own supported operation and preflight.

## Connection health

`route-steward health --target <route-id>` keeps configuration audit separate from actual client usability. It audits the Route, starts the pinned official Hysteria2 client with an ephemeral loopback HTTP proxy, and sends bounded requests through the Route to ipify's IPv4/IPv6 endpoints and Cloudflare's trace endpoint. The result layers server reachability, server audit, Hysteria2 handshake, real Internet access, DNS, declared exit identity, IPv4/IPv6, request latency, and relay WireGuard evidence.

Health is read-only with respect to desired and remote state. It may download the checksum-verified helper into `<private>/tools/` on first use and records sanitized disposable evidence in `observed.json`. Ephemeral configuration under `<private>/health/` contains live Route credentials, stays owner-only, and is removed when the check ends. Public IP values remain omitted from machine output unless the caller explicitly requests them. A failed health check does not authorize repair or replacement.

## ClientTargets

Renderers consume a ClientTarget plus its referenced Profile.

Current renderers:

- `mihomo` — private Hysteria2 Routes plus zero or more explicitly included generic Providers;
- `karing` — the same deterministic private Clash YAML contract, with a Karing 1.2.23.2606 compatibility baseline and mandatory Hysteria2 certificate pinning;
- `shadowrocket` — offline node import or target-scoped private subscription import;
- `hysteria2` — official-client JSON for one explicitly selected managed Route, with HTTP and SOCKS5 sharing one loopback listener.

A Provider is optional. A clean private-only setup must render without one. Blank Profile policy uses generic privacy behavior; geography-specific policies are explicit opt-ins.

The headless renderer defaults to `127.0.0.1:1080` and `auto` ingress selection (IPv4 first, then IPv6). Public/LAN listeners fail closed. It does not silently compose Profile Providers or GUI policy, and separate concurrent targets need separate local ports.

`route-steward proxy --target <client-target> --check` renders the target, obtains the checksum-verified official Hysteria2 client from the private cache, makes one real HTTP request through the Route, compares its IPv4 exit with desired state, and stops. Plain `proxy` runs the same target in the foreground for a service manager or job supervisor. The check contacts ipify and does not return the observed address.

Renderer compatibility is explicit: external client documentation may motivate a new renderer but does not make it supported automatically.

## Private subscription

Subscription state is **ClientTarget-scoped**. Publication resolves one Shadowrocket target, uses an isolated Worker/host identity, generates/uses the target-local bearer token, exports the exact current node list, runs strict Wrangler validation, deploys the selected Worker, verifies the endpoint, and rebuilds local target/render state.

Token rotation is `credential-change`, requires explicit current authorization, is crash-recoverable through a local pending token, and is not exposed through generic MCP execute. It changes only the selected ClientTarget token/publication.

Cloudflare authentication belongs to the user's local Cloudflare/Wrangler environment. RST must not print auth tokens or silently modify DNS zones/unrelated Workers.

Cloud-hosted agents may see the tool arguments required for an operation, including server IP, SSH username, local key path, and selected IDs. Use an offline runtime when those values must remain local to the operator machine.

## Migration

Infrastructure migration is a persisted, retry-safe overlap-first workflow composed from the same deterministic primitives:

1. inspect current Route/dependencies;
2. add replacement Server/Link/Route capacity as required;
3. deploy replacement while old capacity remains enabled;
4. audit and run a real Hysteria2 health check against the replacement;
5. only after a healthy result, switch the relevant Profile selections, render affected ClientTargets, and republish existing subscription-backed targets;
6. if rendering/publication fails or the process is interrupted, restore the old selection before retrying and recheck replacement health;
7. record the completed switch while leaving old remote services and cloud capacity intact;
8. only then consume separately explicit destructive authority for old-capacity retirement if requested.

`migrate-route` can create the BYO replacement Server from supplied structured context or use an existing Server. Direct and relay Routes are supported; relay replacement creates a new matching WireGuard Link. The private `migrations.json` checkpoint makes repeated calls deterministic and records a bounded failure code rather than raw transport output. A blocked workflow returns `workflow-blocked`; retry with the same source Route and replacement Server. A migration request never implies cloud deletion.

## Backup and recovery

Backup creates an encrypted local recovery artifact from canonical schema-1 private state, including any active migration checkpoint and its required SSH material. Decryption credentials must not be passed through model-visible command arguments or logs.

Recovery is local-first: restore to a clean private root, verify the SHA-256 manifest, reject unsafe paths/symlinks, relocate SSH material, validate the restored current inventory, reset observed evidence, then decide whether any remote repair/deployment is needed. Restored migrations are marked `recovery-revalidation-required` and resume before deployment/health rather than trusting old evidence. Chat history is never a recovery source of truth.

## Contributor/debug interfaces

The PowerShell libraries and entry point remain compatibility and regression surfaces for existing callers. They are not a runtime dependency or a second product UI. Remote Bash payloads remain the deployed host implementation and are embedded in the native executable.

When a capability is missing, extend the deterministic core and its behavior tests rather than teaching users a manual shell/SSH workaround.
