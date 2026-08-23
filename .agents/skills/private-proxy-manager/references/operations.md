# PPM machine operations

`agent/ppm-agent.ps1` is the canonical local machine surface. These calls are for the operating agent/runtime.

## Discovery

- `capabilities`: operations, drivers, renderers, required context, effects, executors, and authorization classes.
- `bootstrap`: idempotently create neutral schema-1 private state.
- `context`: sanitized inventory schema, counts, Profiles, ClientTargets, and supported-operation summary.
- `drift`: sanitized desired-versus-observed Route and ClientTarget-render evidence.

Inventory schema `1` is the first public desired-state contract.

## Preflight and execution

Call `preflight` with the operation, optional target, and structured context before every mutation. Inspect `context_complete`, `authorized`, `ready`, `missing_context`, `conflicts`, `user_decisions`, `expected_effects`, and `authorization_class`.

Execute only when `ready=true`. Prefer JSON over stdin so private context does not need to appear in process arguments. Pass local secret references or paths, never secret contents.

## Implemented operations

- `status`: sanitized local state.
- `drift`: desired-versus-observed evidence.
- `audit`: bounded read-only verification for one Route.
- `bootstrap`: neutral local private state.
- `add-server`: local BYO SSH Server registration.
- `add-link`: local WireGuard Link allocation and canonical keys.
- `add-route`: local Hysteria2 Route allocation and canonical credentials.
- `add-provider`, `update-provider`, `remove-provider`: optional generic Provider lifecycle.
- `add-profile`, `update-profile`, `remove-profile`: reusable selection lifecycle.
- `add-client-target`, `update-client-target`, `remove-client-target`: renderer/delivery lifecycle.
- `deploy-route`: deterministic remote deployment followed by audit and rendering.
- `render-client`: private artifacts and hash-only render evidence.
- `publish-subscription`: isolated private Cloudflare delivery for one Shadowrocket ClientTarget.
- `rotate-subscription-token`: explicitly approved target-scoped credential change.
- `backup`: encrypted local recovery archive through a local password prompt.
- `recover`: local-assisted restore into a clean private directory.
- `migrate-route`: overlap-first workflow composed from add, deploy, audit, and render operations.

## Neutral bootstrap

Bootstrap does not select geography, Provider, policy, Profile, client, subscription delivery, or AI vendor. Gather actual context and create only the objects the user needs.

## Remote ownership

Deployment and uninstall own only PPM-namespaced resources and named policy files. Unrelated proxy, WireGuard, service, package, account, firewall, and host-file state remains outside PPM ownership.

## Failure behavior

Keep raw secret-bearing stderr local. Surface a sanitized cause and next action.

Remote transport or audit failure becomes `undetermined`, not permission to repair. If a remote change succeeded before a later validation step failed, report the partial outcome accurately.
