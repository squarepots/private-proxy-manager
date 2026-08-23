# Contributing

Private Proxy Manager is intentionally narrow: it lets capable AI agents safely operate a person's private proxy infrastructure through one model-neutral deterministic core.

## Before changing code

Read `AGENTS.md`, `.agents/skills/private-proxy-manager/SKILL.md`, `ARCHITECTURE.md`, `SECURITY.md`, and `docs/THREAT-MODEL.md`.

Keep these boundaries intact:

- natural-language agent interaction is the only first-class user interface;
- `agent/ppm-agent.ps1` is the sanitized machine contract;
- MCP/runtime adapters stay thin and contain no duplicated business logic;
- canonical desired state and secrets remain local/ignored;
- every mutation fails closed behind the Context Completeness Gate;
- Steward Mode does not expand user authority;
- Providers are optional;
- migration is overlap-first;
- no GUI/panel/TUI/billing/traffic-surveillance/hosted control plane is added to the personal product.

## Scope

Good changes reduce user burden, improve deterministic safety/reliability, add a well-tested capability/renderer/driver, or make the repository easier for an unfamiliar capable agent to operate.

Do not add protocol/provider/client breadth only to increase a feature count. A new capability should have a clear user outcome, machine-readable capability truth, preflight requirements, safe execution semantics, and tests.

## Private data

Never put real infrastructure values in a contribution. Use documentation ranges/domains such as `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `2001:db8::/32`, and `example.invalid`.

Before sharing a change, run the repository's tracked-tree secret/public-content checks and the relevant tests. Generated client files, credentials, recovery archives, local inventory/observed/operator state, Provider URLs, SSH material, and subscription state must remain ignored/private.

## Validation

Use `scripts/Validate-Local.ps1 -Quick` during rapid iteration. Before a PR/release, run `scripts/Validate-Local.ps1` on a machine with the relevant local toolchains; it executes the deterministic PowerShell/public-tree suite and, when available, encrypted-recovery, MCP, Worker, Bash, and ShellCheck validation.

The hosted PR CI remains the independent cross-platform integration boundary and covers:

- tracked-tree secret/public-content checks;
- static architecture/template and release-contract checks;
- agent bootstrap, capability discovery, context gates, and Steward Mode;
- generic migration/state validation;
- ClientTarget rendering with and without Providers;
- observed state and sanitized drift;
- private subscription state/export;
- encrypted recovery behavior;
- local stdio MCP type checking;
- server shell validation;
- Worker type checking/tests/dry-run.

Add or update tests with behavior changes. Do not weaken a safety assertion merely to make a new workflow pass.

## Pull requests and releases

Use a clear, outcome-oriented PR title. Before a PR is ready to merge, review the final diff, make sure the branch is current with the target branch, classify `Version impact` as `none`, `patch`, `minor`, or `major`, and record the decision in the PR body.

For `none`, keep `version.txt` equal to the current target-branch version. For `patch`, `minor`, or `major`, run `scripts/Bump-Version.ps1` once from that current base so the PR contains the exact intended successor version. If the target branch advances or the scope changes, recompute from the new base instead of bumping the provisional branch version again.

Do not bump product versions per commit, push, or intermediate work. Release automation publishes an already-prepared version from `main`; it does not decide or modify SemVer. See `docs/RELEASING.md`.

## Third-party material

Preserve license/notice files for vendored code. The current vendored QR generator retains its own MIT license and notice under `client/vendor/`.

## Compatibility

Some server-side service and path identifiers are deployed ABI. Do not rename them casually without checking existing installations and uninstall behavior. Product-facing concepts and new code should use the Private Proxy Manager model.
