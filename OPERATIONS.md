# Operations

This document describes PPM's **internal machine-operation contract for agents and contributors**. It is not end-user onboarding. Normal users describe intent in conversation; the active AI agent owns discovery, context gathering, preflight, execution, validation, and explanation.

## Canonical machine surface

`agent/ppm-agent.ps1` is the stable local machine interface. It emits sanitized JSON envelopes and operates against the selected private instance root (`-PrivateDirectory`, defaulting to ignored local `private/`).

Hosts with local MCP support may use `mcp/`, which is a thin stdio adapter over the same surface. MCP does not duplicate state, business logic, renderers, or authorization.

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
<private>/delivery/         generated ClientTarget artifacts + hash-only render manifest
<private>/recovery/         encrypted recovery artifacts
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

PPM does not publish conversion logic for development-only schemas that were never public. Recovery accepts the current public desired-state schema only. There is no independent persisted `model_version` axis.

## Capability discovery

Do not hard-code assumptions from this document into runtime adapters. Ask the machine surface for capabilities and driver truth.

Initial operation families include:

- local read: status/context/drift;
- remote read: supported Route audit;
- local desired-state writes: Server/Link/Route/Provider/Profile/ClientTarget lifecycle;
- local private output: render ClientTarget, backup;
- remote PPM write: deploy Route;
- external configuration publication: private subscription publication;
- guarded target-scoped credential change: subscription-token rotation;
- workflow-level migration/recovery.

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

A new WireGuard Link references existing entry/exit Servers, allocates collision-free PPM-native interface/port/subnet resources, and generates canonical key material locally. Adding it does not deploy remotely.

### Route

A new direct or relay Route references existing topology, allocates a listener when needed, generates canonical Hysteria2 credentials/certificate/payload locally, and starts `pending` / disabled. It becomes enabled only after deterministic deployment succeeds.

### Provider

A generic Provider is optional. Its URL is stored only in local secret storage. Provider update is transactional and removal is blocked while a Profile references it.

### Profile / ClientTarget

Profile lifecycle changes reusable selection only. A new Profile does not silently select a geography-specific policy. ClientTarget lifecycle changes concrete renderer/delivery identity. Removing a Profile is blocked while a ClientTarget references it. Removing a subscription-backed ClientTarget is blocked until its external subscription state has been explicitly retired/revoked.

## Deployment ownership

A Route deployment uses repository-owned deployment internals through the execution library. Agent-facing execution captures lower-level output so the machine protocol remains clean.

PPM owns its `/usr/local/lib/private-proxy-manager`, `/etc/private-proxy-manager`, `/var/lib/private-proxy-manager`, `private-proxy-manager-*` systemd units, `ppm-hysteria` runtime user, `wg-ppm*` Link interfaces, generated files, and individually named policy files. The initial host preparation also changes global UFW defaults, swap/fstab, SMTP egress, SSH/sysctl/journald, package, unattended-upgrades, and vnstat state.

Use only a dedicated, rebuildable Ubuntu 24.04 amd64 host. Deployment/uninstall must not delete, disable, overwrite, or require the absence of unrelated Xray/Hysteria/WireGuard software. Uninstall removes PPM-owned artifacts and named policy files but does not restore unknown prior UFW defaults, swap/fstab, packages, or global host behavior.

An already-deployed Route is read-only audited before overwrite. If the current remote state is drifted or undetermined, deployment refuses to overwrite it until the discrepancy is understood.

After deployment, the agent performs read-only audit, updates sanitized observed evidence, and records current ClientTarget render hashes.

## Audit and drift

Remote audit emits only bounded typed evidence into the deterministic core. Agent/MCP output never receives raw SSH/server diagnostics.

Supported drift categories include `service-missing`, `remote-config-mismatch`, `firewall-network-mismatch`, `wireguard-link-mismatch`, `hysteria-listener-mismatch`, `certificate-mismatch`, `egress-mismatch`, `client-render-stale`, `undetermined`, and in-sync/disabled/never-audited informational states.

Observed evidence is disposable. Drift does not self-heal; repair requires its own supported operation and preflight.

## ClientTargets

Renderers consume a ClientTarget plus its referenced Profile.

Current renderers:

- `mihomo` — private Hysteria2 Routes plus zero or more explicitly included generic Providers;
- `shadowrocket` — offline node import or target-scoped private subscription import.

A Provider is optional. A clean private-only setup must render without one. Blank Profile policy uses generic privacy behavior; geography-specific policies are explicit opt-ins.

Renderer compatibility is explicit: external client documentation may motivate a new renderer but does not make it supported automatically.

## Private subscription

Subscription state is **ClientTarget-scoped**. Publication resolves one Shadowrocket target, uses an isolated Worker/host identity, generates/uses the target-local bearer token, exports the exact current node list, runs strict Wrangler validation, deploys the selected Worker, verifies the endpoint, and rebuilds local target/render state.

Token rotation is `credential-change`, requires explicit current authorization, is crash-recoverable through a local pending token, and is not exposed through generic MCP execute. It changes only the selected ClientTarget token/publication.

Cloudflare authentication belongs to the user's local Cloudflare/Wrangler environment. PPM must not print auth tokens or silently modify DNS zones/unrelated Workers.

Cloud-hosted agents may see the tool arguments required for an operation, including server IP, SSH username, local key path, and selected IDs. Use an offline runtime when those values must remain local to the operator machine.

## Migration

Infrastructure migration is an agent-orchestrated overlap-first workflow composed from deterministic primitives:

1. inspect current Route/dependencies;
2. add replacement Server/Link/Route capacity as required;
3. deploy replacement while old capacity remains enabled;
4. audit replacement;
5. render/update clients;
6. confirm replacement usability;
7. only then consume separately explicit destructive authority for old-capacity retirement if requested.

A migration request does not imply immediate cloud deletion.

## Backup and recovery

Backup creates an encrypted local recovery artifact from canonical schema-1 private state. Decryption credentials must not be passed through model-visible command arguments or logs.

Recovery is local-first: restore to a clean private root, verify the SHA-256 manifest, reject unsafe paths/symlinks, relocate SSH material, validate the restored current inventory, reset observed evidence, then decide whether any remote repair/deployment is needed. Chat history is never a recovery source of truth.

## Contributor/debug interfaces

Lower-level PowerShell/scripts remain available for tests, debugging, and implementation work. They are not a second product UI and should not be documented as something normal users must learn.

When a capability is missing, extend the deterministic core and its behavior tests rather than teaching users a manual shell/SSH workaround.
