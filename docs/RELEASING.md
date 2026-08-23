# Releasing Route Steward

`version.txt` is the only RST product-version authority. Persisted inventory schema and dependency/protocol versions are separate compatibility domains; there is no independent object-model version axis.

## PR version decision

Before a PR is ready to merge:

1. Review the final diff.
2. Make sure the branch is current with the latest target branch.
3. Classify version impact as exactly one of `none`, `patch`, `minor`, or `major`.
4. Record the decision and a short reason in the PR body.
5. For `none`, leave `version.txt` equal to the target-branch version. For `patch`, `minor`, or `major`, run `scripts/Bump-Version.ps1` once from that current base so the branch contains exactly the intended successor version.
6. Do not bump versions per commit, push, or intermediate work.
7. If the target branch advances or the final scope changes before merge, recompute from the new base rather than stacking another bump on the provisional branch version.

The PR body is an audit record. CI does not decide SemVer from the PR title, labels, body, commits, or diff.

## Publication flow

Release automation publishes the product version already present on `main`; it never changes source or decides version impact.

```text
PR-ready branch -> prepared version -> CI -> merge -> tag existing main commit -> GitHub Release
```

A merge with `Version impact: none` leaves `version.txt` unchanged and therefore does not trigger automatic publication. A merge that changes `version.txt` triggers the Release workflow in the public repository.

The workflow:

- validates plain SemVer from `version.txt`;
- treats an already-published version as a no-op;
- rejects a version lower than or equal to the latest release when no matching tag exists;
- creates an annotated `vX.Y.Z` tag on the existing `main` commit and a GitHub Release with generated notes;
- never calls the bump script, edits `version.txt`, creates a release commit, or opens a release PR.

The repository `GITHUB_TOKEN` is the release credential. No long-lived release token is part of the normal contract.

Exceptional races or partial GitHub failures should fail visibly and be recovered explicitly rather than introducing a release queue, ledger, or reconciliation state machine.

## First release

Before any release, run the public CI/validation boundary and confirm the source tree contains no real inventory, credentials, Provider/subscription URLs, SSH material, generated client artifacts, recovery material, or other private state.

When no `v*` SemVer tag exists, automatic publication from a `version.txt` push remains intentionally idle; `workflow_dispatch` may publish the exact current `version.txt` as the first release. After that release exists, later version-changing merges publish automatically.

## Validation

Before publishing any release:

- run the repository secret/public-tree checks and applicable PowerShell, shell, MCP, and Worker tests;
- confirm `agent/route-steward-agent.ps1 capabilities` reports the same product version as `version.txt`;
- confirm `docs/COMPATIBILITY.md` matches the shipped capability boundary;
- keep all real operational state outside Git.
