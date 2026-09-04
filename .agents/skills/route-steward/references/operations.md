# Machine operations

The `route-steward` executable returns sanitized JSON through the CLI and local stdio MCP server. Run `capabilities` for the current operation list, required context, effects, executors, and authorization classes.

## Typical sequence

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
route-steward drift --private-dir ./private
route-steward preflight --private-dir ./private --operation add-server --context-stdin
route-steward execute --private-dir ./private --operation add-server --context-stdin
```

Bootstrap is needed only for a new private root. Existing setups begin with `context`, `drift`, and any relevant migration checkpoint.

For each mutation, inspect `context_complete`, `authorized`, `ready`, `missing_context`, `conflicts`, `user_decisions`, `expected_effects`, and `authorization_class`. Execute when `ready=true`. Send private structured context over stdin where possible.

## Validation and continuity

```text
route-steward audit --private-dir ./private --target route-a
route-steward health --private-dir ./private --target route-a
route-steward migrations --private-dir ./private
route-steward proxy --private-dir ./private --target backend-a --check
route-steward proxy --private-dir ./private --target backend-a
route-steward mcp --private-dir ./private
```

`health` tests real Hysteria2 traffic through a deployed Route. `proxy --check` tests one loopback Hysteria2 ClientTarget; plain `proxy` stays in the foreground for supervision by the caller.

`migrate-route` records its source, replacement, phase, and next action in the private root. Retry `workflow-blocked` with those recorded identities.

## Failure handling

Keep raw stderr and private files local. Report the sanitized failure code, known partial effects, and next action.

Remote transport or audit failures produce `undetermined` evidence. A later validation failure may follow a successful remote change, so report both facts. Old migration capacity remains available after the client switch until the user requests retirement.
