# PPM machine operations

`agent/ppm-agent.ps1` is the canonical local machine surface. These examples are for the operating agent/runtime, not end-user onboarding.

## Discovery

Use these before assuming project state or capability:

- `capabilities`: supported/guarded operations, driver truth, executors, and authorization classes.
- `bootstrap`: idempotently create neutral schema-1 private state.
- `context`: sanitized counts, inventory schema, Profiles, ClientTargets, mode, and capability summary.
- `drift`: sanitized desired-vs-observed Route categories plus ClientTarget render drift.
- `mode`: read or set `collaborative` / `steward`.

There is no public state-upgrade operation. Inventory schema `1` is the first public persisted desired-state contract.

## Context gate

For mutations, call `preflight` with an operation, optional target, and structured context. The important fields are `context_complete`, `authorized`, `ready`, `missing_context`, `conflicts`, `user_decisions`, `expected_effects`, and `authorization_class`.

Do not call `execute` until `ready` is true.

Use structured JSON from stdin where the runtime supports it so complex/private context does not need to appear in process arguments. Do not put private keys or secret contents in the context object; reference local paths/identities when required by the operation.

## Operations

- `add-server`: local desired-state registration only; current compute driver is `byo-ssh`.
- `add-link`: local WireGuard Link allocation + canonical local keys; no remote write.
- `add-route`: local Hysteria2 Route credentials/payload + desired state; Route remains pending/disabled.
- `add-provider`, `update-provider`, `remove-provider`: optional generic Provider lifecycle with URL in private secret storage.
- `add-profile`, `update-profile`, `remove-profile`: reusable Route/Provider/policy selection lifecycle.
- `add-client-target`, `update-client-target`, `remove-client-target`: renderer/delivery target lifecycle referencing a Profile.
- `deploy-route`: deterministic PPM-owned remote deployment, then typed audit and ClientTarget render.
- `audit`: read-only remote verification; raw evidence stays below the agent boundary, sanitized typed category goes to the agent.
- `render-client`: local ClientTarget artifact rendering and hash-only render-manifest update; Provider is optional.
- `publish-subscription`: optional **ClientTarget-scoped** private Cloudflare Worker delivery. If uninitialized, preflight requires an isolated Worker identity + hostname.
- `rotate-subscription-token`: guarded target-scoped `credential-change`; requires explicit current authorization and is not exposed by generic MCP execute.
- `backup`: encrypted local recovery archive through a local secure password prompt.
- `migrate-route`: overlap-first workflow; it never implies immediate retirement/deletion.
- `recover`: local-assisted restore into a clean private directory, schema-1 validation, then read-only audit before remote mutation.

## Neutral bootstrap

Bootstrap does not choose geography, Provider, Profile policy, client application/device targets, or subscription delivery. Gather actual user context and explicitly create the required Profile/ClientTarget objects afterward.

## Profile and ClientTarget

Do not use Profile as renderer/device identity. Profile selects Routes, optional Providers, and Policy. ClientTarget references one Profile and owns `renderer` + delivery semantics.

## Remote ownership

Deployment/uninstall owns only PPM-namespaced resources. Unrelated Xray/Hysteria/WireGuard state is not PPM state and must not be removed or treated as a cleanup target.

## Guarded/external actions

`rotate-subscription-token`, generic credential rotation, server deletion, and paid resource purchase must never be inferred from Steward Mode. Credential-change/destructive/paid-external classes require explicit current user authority.

Cloud/server lifecycle and purchases are not silently implemented by the PPM core.

## Failure behavior

If a machine operation fails, do not paste raw secret-bearing stderr into chat. Inspect locally, use safe evidence, and surface only the useful cause/next decision.

Remote audit transport failure becomes `undetermined`, not permission to repair. A deployed Route with drift/undetermined state is not blindly overwritten.

A remote change that succeeded before a later validation/render failure must be reported accurately; do not claim rollback unless it actually happened.
