# Migration and recovery

## Infrastructure migration

Migration is an Agent-orchestrated workflow, not a delete-and-recreate command.

1. Inspect current desired state and typed drift.
2. Establish replacement server/access and any current external facts needed to choose it.
3. Add replacement Server/Link/Route desired state while the old path remains usable.
4. Preflight and deploy the replacement through repository-owned operations.
5. Audit the replacement and confirm the declared exit is in sync.
6. Render/update supported ClientTargets and ensure render drift is clear.
7. Keep old capacity until the replacement is proven in the user's relevant clients/path.
8. Retirement/termination of old capacity is a separate destructive action requiring explicit current authorization.

Do not interpret “migrate” as “delete old server immediately.” Generic MCP execute intentionally does not expose a one-shot migration action; compose supported primitives so each gate/effect remains explicit.

## Recovery

Canonical recovery comes from the encrypted recovery archive containing current schema-1 local desired state, secrets, operator context, and SSH material. Observed state and ClientTarget render evidence are disposable.

Use repository-owned `scripts/Restore-RecoveryArchive.ps1` for the restore primitive. The archive password is intentionally **not** accepted through Agent/MCP JSON, process arguments, repository files, or environment variables. The script asks 7-Zip to prompt locally; tell the user only to enter the password in that local secure prompt.

Recovery sequence:

1. choose a clean destination private directory; never overwrite existing state;
2. invoke the restore primitive and let the user satisfy the local password prompt;
3. the primitive verifies the archive manifest, rejects links/unsafe paths, relocates SSH/private delivery paths, applies owner-only permissions, validates the restored schema-1 inventory, and resets `observed.json`;
4. inspect capabilities/context/drift from restored state;
5. do not assume remote infrastructure matches restored desired state;
6. audit existing Routes before any remote write;
7. render clients only from validated canonical state;
8. redeploy only scoped resources that are actually missing/drifted and covered by the user's current intent.

The restore primitive reports `REMOTE_INFRASTRUCTURE_CHANGED=0`. Recovery must not depend on one AI vendor/runtime or on chat history.

PPM's first public desired-state contract is schema `1`. Recovery does not publish or preserve converters for development-only schemas that were never public contracts.
