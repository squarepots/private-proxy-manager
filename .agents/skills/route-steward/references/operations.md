# RST machine operations

The native `route-steward` executable is the canonical local machine surface. It provides both CLI JSON and the in-process local stdio MCP server. These calls are for the operating agent/runtime.

## Discovery

- `capabilities`: operations, drivers, renderers, required context, effects, executors, and authorization classes.
- `bootstrap`: idempotently create neutral schema-1 private state.
- `context`: sanitized inventory schema, counts, Profiles, ClientTargets, and supported-operation summary.
- `drift`: sanitized desired-versus-observed Route and ClientTarget-render evidence.
- `health`: on-demand real Hysteria2 client traffic check for one deployed Route.
- `migrations`: sanitized resumable migration checkpoints, optionally filtered by source Route.
- `proxy`: render and run one loopback-only Hysteria2 ClientTarget; `--check` validates real HTTP traffic and exit identity, then exits.

Inventory schema `1` is the first public desired-state contract.

## Preflight and execution

Call `preflight` with the operation, optional target, and structured context before every mutation. Inspect `context_complete`, `authorized`, `ready`, `missing_context`, `conflicts`, `user_decisions`, `expected_effects`, and `authorization_class`.

Execute only when `ready=true`. Prefer structured context over stdin so private values do not appear in process arguments. Pass local secret references or paths, never secret contents.

Representative calls:

```text
route-steward capabilities
route-steward health --private-dir ./private --target route-a
route-steward migrations --private-dir ./private
route-steward proxy --private-dir ./private --target backend-a --check
route-steward proxy --private-dir ./private --target backend-a
route-steward preflight --private-dir ./private --operation add-server --context-stdin
route-steward execute --private-dir ./private --operation add-server --context-stdin
route-steward execute --private-dir ./private --operation migrate-route --target route-a --context-stdin
route-steward mcp --private-dir ./private
```

## Implemented operations

- `status`: sanitized local state.
- `drift`: desired-versus-observed evidence.
- `audit`: bounded read-only verification for one Route.
- `health`: server audit plus real client handshake, Internet, DNS, exit identity, IP-family, latency, and relay checks.
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
- `migrate-route`: persisted, retry-safe overlap-first Server/Link/Route replacement with health-gated ClientTarget switching and no automatic retirement.

## Neutral bootstrap

Bootstrap does not select geography, Provider, policy, Profile, client, subscription delivery, or AI vendor. Gather actual context and create only the objects the user needs.

## Remote ownership

Deployment and uninstall own only RST-namespaced resources and named policy files. Unrelated proxy, WireGuard, service, package, account, firewall, and host-file state remains outside RST ownership.

## Failure behavior

Keep raw secret-bearing stderr local. Surface a sanitized cause and next action.

Remote transport or audit failure becomes `undetermined`, not permission to repair. If a remote change succeeded before a later validation step failed, report the partial outcome accurately.

Health contacts ipify's address endpoints and Cloudflare's trace endpoint through the Route. It omits exact public IP values unless the caller explicitly requests them and reports packet loss as unsupported rather than inventing an unstable metric.

Migration returns `workflow-blocked` with a bounded failure code when a stage cannot complete. Retry with the same source Route and `replacement_server_id`; never change the replacement identity of an active transaction. A complete result still reports `old_capacity_retired=false`.

The `proxy` command is local and target-scoped. It may write the private rendered JSON and verified official-client cache. Its check contacts ipify through the selected Route and returns no observed public IP value; the run mode stays in the foreground until stopped.
