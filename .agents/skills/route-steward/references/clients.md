# ClientTargets

RST does not replace proxy client apps. It renders/imports private infrastructure into supported clients.

## Client model

Keep these concepts separate:

- `Profile` — reusable Route / Provider / policy selection. It is not a renderer and not a device identity.
- `ClientTarget` — references one Profile and declares the renderer/delivery contract for a concrete client output.

Multiple ClientTargets may reuse one Profile. Renderer behavior comes only from `ClientTarget.renderer`; Profiles contain reusable selection state and no renderer compatibility marker.

## Current first-class renderers

- `mihomo`: file output for Mihomo-compatible clients such as Clash Verge-compatible clients.
- `karing`: private Clash YAML for Karing, compatibility baseline 1.2.23.2606. Import the generated `.yaml` through Karing's local Clash-file flow without editing it. The renderer requires the managed SHA-256 certificate pin on every Hysteria2 node.
- `shadowrocket`: offline node import, or optional target-scoped private subscription delivery.
- `hysteria2`: private official-client JSON for a Linux server, backend, script, or CI job. It selects one enabled Route from the referenced Profile and exposes HTTP and SOCKS5 on one loopback-only listener.

Do not hard-code operating-system identities such as `windows` or `iphone` into core behavior. ClientTarget IDs are project identities, not operating-system drivers.

## Choosing a target

Infer the ClientTarget from the user's stated device/app when unambiguous. If current compatibility is version-sensitive or the app is unfamiliar, research authoritative client documentation before selecting a renderer.

External documentation can establish that a client understands a format/protocol; it does not make that client supported by RST. If there is no RST renderer/tested import contract, describe it as unsupported rather than improvising a config.

## Providers

Third-party `Provider` nodes are optional. A private-only setup with zero Providers must render successfully.

When a Profile explicitly includes Providers, compose only those enabled Provider IDs. Do not impose provider-specific grouping, naming, health checking, or routing policy that was not declared by the Profile.

The `hysteria2` renderer deliberately uses one explicitly selected managed Route. It does not compose Providers or apply GUI routing policy, and `auto` ingress selection prefers IPv4 before falling back to IPv6. Use distinct listener ports when multiple local proxies run concurrently.

## Headless runtime

`route-steward proxy --target <id> --check` downloads the pinned official client into the private cache when absent, renders the target, makes a real HTTP request through it, and compares the exit with desired state. Plain `route-steward proxy --target <id>` runs the same verified client in the foreground for supervision by a shell, service manager, or CI job. Never widen the generated listener beyond loopback.

## Shadowrocket delivery

The offline HTML artifact contains private import QR data and must not load external scripts/resources.

The optional Cloudflare Worker is a private configuration-delivery endpoint only. Subscription state belongs to one Shadowrocket ClientTarget. Each subscription-backed ClientTarget requires an isolated Worker/host identity and its own bearer token state.

Token rotation is a `credential-change` operation. It requires explicit current authorization, republishes only that target's Worker body/token, and must not rotate Route credentials or another ClientTarget's token.

The Worker is not a proxy data plane, management database, panel, telemetry service, or account system. Keep subscription token/body in Worker secrets and canonical recovery state locally.

## Validation and render drift

Validate generated Mihomo/Karing Clash configuration with a compatible local core when available. Karing output also passes a renderer-specific pinned-Hysteria2 structure check. Validate a headless Hysteria2 target with the dedicated real-traffic check before depending on it. Keep output private and restrict local permissions.

RST records only local input/output hashes needed to detect a stale or missing canonical ClientTarget render. A stale render is drift, not permission to mutate remote infrastructure.

Never paste generated live configuration, subscription URLs, or full private node URIs into conversation just to prove rendering succeeded.
