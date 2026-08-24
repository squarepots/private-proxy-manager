# Migration and recovery

## Infrastructure migration

Migration is an overlap-first workflow:

1. inspect current desired state and drift;
2. establish replacement server access and current external facts;
3. add replacement Server, Link, and Route state while the working path remains available;
4. preflight and deploy the replacement through repository-owned operations;
5. audit the replacement, run health, and confirm real traffic through the declared exit;
6. render affected ClientTargets and clear render drift;
7. confirm the replacement works in the relevant client path;
8. handle old external capacity later as a separate user-requested action.

`migrate-route` persists this composition in private `migrations.json` and advances it through deterministic checkpoints. It may add a supplied BYO replacement Server, creates a matching replacement Link/Route, deploys without rendering, requires a healthy end-to-end check, then switches affected Profile selections and ClientTargets. Existing subscription targets are republished. A failed switch restores the old selection; an interrupted switch enters a recorded rollback path. Retry the same source Route and replacement Server when the result is `workflow-blocked`.

The old Route is removed from client selection only after the replacement is healthy. Its remote service and external capacity are not uninstalled or deleted. Retirement always remains a separate, explicitly authorized destructive request. The dedicated `route_steward_migrate` MCP tool owns this workflow; generic MCP execute still excludes it.

## Recovery

The encrypted recovery archive contains schema-1 desired state, secrets, SSH material, and any active migration checkpoint. Observed and render evidence can be regenerated. Restored migration stages are moved back to a revalidation point; query `migrations`, then resume the same source/replacement identity so deployment, audit, and health run again.

Create an archive with `route-steward backup --private-dir <directory>`. Restore it into a clean destination with `route-steward recover --archive <path> --private-dir <directory>`. From a source checkout, replace `route-steward` with `go run ./cmd/route-steward`. The archive password is accepted only by the local 7-Zip prompt, never Agent/MCP JSON, process arguments, repository files, environment variables, or chat. The PowerShell recovery scripts remain compatibility entry points, not the canonical agent path.

Recovery sequence:

1. choose a clean private destination;
2. invoke `route-steward recover` and enter the password in the local prompt;
3. verify manifest and path safety, relocate SSH/delivery paths, apply private permissions, validate inventory, and reset `observed.json`;
4. inspect capabilities, context, and drift;
5. audit existing Routes before any remote write;
6. render clients from validated canonical state;
7. deploy only a scoped resource that evidence shows is missing or drifted and the user's current goal covers.

Older archives may contain deprecated `operator.json`; recovery verifies the archive manifest and ignores that file.

Recovery reports no remote infrastructure change and does not depend on the original model or chat history.
