# Architecture

Route Steward is a **model-agnostic, local-first lifecycle core for self-hosted network paths**. Natural-language conversation belongs to the host agent; durable infrastructure semantics belong to RST.

```text
Human
  ↓ natural-language intent
Capable AI agent/runtime
  ├─ learns repository
  ├─ gathers context
  ├─ researches current external facts when useful
  ├─ respects user authority
  └─ uses RST machine operations
          ↓
Portable integration layer
  ├─ canonical Skill/instructions
  └─ native CLI + in-process local stdio MCP
          ↓
Deterministic RST core
  ├─ desired state + secrets
  ├─ capabilities + preflight
  ├─ deploy + typed audit + drift
  ├─ ClientTarget rendering
  ├─ subscription delivery
  └─ migration/recovery primitives
          ↓
Operator-controlled infrastructure and private client artifacts
```

The core never branches on model/vendor identity. Runtime-specific files delegate to the same machine contract rather than creating separate RST editions.

## Product objects and drivers

- **Server** — stable identity for bring-your-own supported Linux compute. Initial compute driver: `byo-ssh`.
- **Link** — first-class inter-server link. Initial driver: single-hop `wireguard`.
- **Route** — logical network path offered to ClientTargets. A `direct` Route uses one Server; a `relay` Route references ingress Server, egress Server, and Link. Initial ingress driver: `hysteria2`.
- **Provider** — optional upstream third-party node source. Initial source type: generic `mihomo-http`.
- **Policy** — reusable client routing/DNS behavior where a renderer needs it.
- **Profile** — reusable selection of Routes, optional Providers, and Policy. It is not a renderer or device identity.
- **ClientTarget** — concrete renderer/delivery identity referencing a Profile. Current renderers: `mihomo`, `karing`, `shadowrocket`, and headless `hysteria2`.
- **Private subscription** — optional target-scoped delivery state for one Shadowrocket ClientTarget.

These concepts make the core deterministic. They are not concepts the user must learn before using the product.

## State layers

```text
<private>/inventory.json    canonical desired infrastructure/client state
<private>/secrets/          canonical secret material and secret index
<private>/observed.json     disposable sanitized remote audit evidence
<private>/delivery/         generated private client artifacts + hash-only render manifest
<private>/recovery/         encrypted recovery artifacts
```

`<private>` is the selected private instance root. It may be ignored local `private/` or an external directory supplied through `--private-dir`. Tracked product source contains none of the real values above.

Desired state is canonical. Observed state and render-manifest state are disposable evidence that can be recreated by read-only audit or deterministic rendering.

## State compatibility

Inventory schema `1` is the current persisted desired-state contract. It directly expresses Server/Link/Route drivers, optional Providers, Profiles, and ClientTargets.

RST does not publish compatibility machinery for development-only schemas that were never part of a public release. Recovery accepts the current public schema only. There is no independent persisted `model_version` axis.

Product SemVer is a separate compatibility domain and is owned by `version.txt`.

## Neutral bootstrap

Clean bootstrap creates valid empty schema-1 desired state, an empty secret index/observed state, and private delivery/recovery locations. It does **not** choose a Server/provider/region, routing policy, Profile, client application/device target, subscription identity, or AI vendor.

The host agent gathers the user's actual context and then creates the required Profile/ClientTarget objects explicitly.

## Preflight contract

Mutation is a two-part contract:

```text
intent + discovered context
        ↓
preflight
  ├─ capability supported?
  ├─ state schema current?
  ├─ target unambiguous?
  ├─ required local state/secrets/access present?
  ├─ dependencies/conflicts known?
  ├─ expected effects known?
  └─ authorization class satisfied?
        ↓
ready=true → deterministic execution
ready=false → gather context / ask human / stop
```

The gate is implemented in local core code and returns machine-readable missing context, conflicts, expected effects, and authorization class. “Complete context” is scoped to the operation rather than perfect knowledge of the project.

## Agent interfaces

The native Go `route-steward` executable is the canonical sanitized machine surface. It exposes capability discovery, neutral bootstrap, context, drift, preflight, supported execution, encrypted recovery, and an in-process **local stdio MCP** server while suppressing raw secret-bearing diagnostics.

The executable is released for Linux, macOS, and Windows on amd64 and arm64. Go owns local state and orchestration; system OpenSSH performs transport, and the unchanged `server/*.sh` payloads remain the remote implementation embedded in the binary. The PowerShell agent entry point is a compatibility forwarder, not a runtime dependency.

Guarded credential rotation is intentionally not part of generic MCP execute. Private structured context may be passed over stdin so sensitive infrastructure context need not appear in process arguments.

## Network model

Initial supported topology:

```text
direct:
client → Hysteria2 entry/exit Server → declared exit

relay:
client → Hysteria2 entry Server → WireGuard Link → exit Server/NAT → declared exit
```

Each new Link receives isolated RST-native interface/UDP-port/subnet resources. Remote deployment and uninstall mutate RST-owned resources and named policy files, while leaving existing firewall, WireGuard, networking software, and other host state in place. The initial host preparation still has documented global effects; the supported host is dedicated and rebuildable.

A Route may optionally own a bounded 2–8-port Hysteria UDP hopping range. The desired-state range, UFW rule, Hysteria listener, scoped systemd capability drop-in, desired configuration hash, canonical payload, client renderers, and migration checkpoint carry the selected value. A relay exit replacement keeps old capacity live, so it reserves a same-width non-overlapping range on the unchanged entry before the health-gated client switch. This is a deliberately narrow response to per-port UDP disruption, not a general answer to UDP-wide blocking.

## ClientTarget rendering

A renderer resolves one ClientTarget, follows its Profile reference, then consumes selected canonical Route payloads and optional Providers.

- Mihomo ClientTargets use file delivery and may compose managed Routes with explicitly selected generic Providers.
- Karing ClientTargets use the tested private Clash YAML contract and retain SHA-256 certificate pinning for every managed Hysteria2 node.
- Shadowrocket ClientTargets render private Hysteria2 node imports or use optional target-scoped subscription delivery.
- Hysteria2 ClientTargets select one enabled Route from their Profile, render official-client JSON, and expose same-port HTTP/SOCKS5 on an IP-literal loopback listener. They intentionally do not approximate GUI policy or Provider composition.

For an enabled hopping Route, the renderer uses Hysteria's standard multi-port endpoint in every supported client contract. The headless client also uses the interoperable fixed 30-second UDP hop interval; arbitrary per-client interval controls are intentionally absent.

Output filenames derive from ClientTarget IDs, not operating-system identities. With no explicit Profile policy, rendering uses the generic privacy behavior; geography-specific policy such as `balanced-cn` is opt-in only.

The agent path records a hash-only render manifest after successful rendering. Stale/missing output becomes `client-render-stale` without exposing private client material.

The native `proxy` command renders the Hysteria2 target and uses the same pinned, checksum-verified official client as Route health. Check mode proves a real HTTP request exits through the declared Route; run mode remains foreground so process supervision is an operator concern rather than a second RST daemon/state layer.

## Private subscription delivery

The optional Worker is deliberately narrow:

```text
ClientTarget + Profile + canonical Route state
  → local Shadowrocket URI export
  → subscription body + token hash as Worker secrets
  → isolated token-protected HTTPS endpoint
  → Shadowrocket refresh
```

Subscription state belongs to one ClientTarget. Different subscription-backed ClientTargets cannot share the same Worker identity or host in the current single-body design.

Token rotation is target-scoped and crash-recoverable. Route credentials and other ClientTarget credentials remain unchanged.

The Worker stores one subscription body and token hash as secrets and serves that private configuration from a non-cacheable HTTPS endpoint. Local inventory remains the source of truth.

## Desired / observed / drift

Audit compares supported remote facts with declared desired state and stores sanitized evidence in `observed.json`. Raw SSH/server diagnostics remain below the agent boundary.

Current drift taxonomy distinguishes RST service absence, remote configuration mismatch, firewall/network mismatch, WireGuard mismatch, Hysteria2 listener mismatch, certificate mismatch, egress mismatch, stale/missing ClientTarget renders, and undetermined state.

An already-deployed Route is audited before overwrite. Drifted or undetermined remote state blocks deterministic overwrite until understood. Drift is evidence, never automatic repair authority.

## Migration and recovery

Infrastructure migration is **overlap-first**:

1. add replacement desired capacity;
2. deploy it while the current Route remains working;
3. audit the replacement;
4. render/update client delivery;
5. only retire old capacity when that destructive step is separately and explicitly authorized.

Recovery treats encrypted local canonical state as the source of truth. Restoration verifies the archive manifest, rejects unsafe paths, relocates private SSH material, validates current schema-1 state, resets observed evidence, and makes no remote changes by itself.

See `docs/COMPATIBILITY.md` for current capability truth and `SECURITY.md` / `docs/THREAT-MODEL.md` for security boundaries.
