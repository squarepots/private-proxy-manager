# Migration and recovery

## Infrastructure migration

Migration is an overlap-first workflow:

1. inspect current desired state and drift;
2. establish replacement server access and current external facts;
3. add replacement Server, Link, and Route state while the working path remains available;
4. preflight and deploy the replacement through repository-owned operations;
5. audit the replacement and confirm the declared exit;
6. render affected ClientTargets and clear render drift;
7. confirm the replacement works in the relevant client path;
8. handle old external capacity later as a separate user-requested action.

`migrate-route` describes and coordinates this composition; generic MCP execute does not turn it into an opaque one-shot remote mutation.

## Recovery

The encrypted recovery archive contains schema-1 desired state, secrets, and SSH material. Observed and render evidence can be regenerated.

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
