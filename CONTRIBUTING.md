# Contributing

Route Steward lets capable AI agents operate self-hosted network paths through one deterministic, model-neutral core.

## Start with the contract

Read `AGENTS.md`, the repository Skill, `ARCHITECTURE.md`, `SECURITY.md`, and `docs/COMPATIBILITY.md`.

Contributions should preserve these boundaries:

- natural-language intent is the user entry point;
- the native `route-steward` CLI and in-process MCP share one sanitized Go machine contract;
- desired state and secrets remain local and ignored;
- every mutation uses fail-closed preflight;
- Providers remain optional;
- migration remains overlap-first;
- remote writes remain inside RST ownership.

## Product changes

Good changes reduce user burden, improve reliability or safety, add a clearly needed and tested capability, or make the repository easier for an unfamiliar agent to operate.

A new driver, renderer, or operation needs:

- a specific user outcome;
- machine-readable capability metadata;
- required context, effects, and authorization semantics;
- deterministic implementation;
- focused behavior tests;
- an update to `docs/COMPATIBILITY.md`.

Keep user-facing onboarding outcome-oriented. Put exact machine semantics in Operations and the repository Skill instead of repeating them across every document.

## Public examples and private data

Use synthetic IDs and reserved values such as `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`, `2001:db8::/32`, and `example.invalid`.

Generated client files, credentials, recovery archives, local inventory/observed state, Provider URLs, SSH material, and subscription state stay outside the tracked tree.

Run the public-tree and secret checks before sharing a change.

## Translations

`README.md` is the canonical product and technical copy. Keep translated READMEs faithful to current behavior, preserve commands, paths, field names, and operation IDs exactly, and write natural prose for the target language. When adding a locale, update the language navigation in every root README.

## Validation

Run the native suite first:

```text
go test ./...
go vet ./...
```

`scripts/Validate-Local.ps1` remains available to contributors for the complete public-tree, compatibility, Worker, Bash, and ShellCheck suite. Public hosted PR CI tests the Go engine on Linux, macOS, and Windows, cross-builds amd64/arm64 release targets, and validates the optional Worker independently.

Add or update focused behavior tests with every contract change.

## Pull requests and versions

Use an outcome-oriented title. Review the final diff, update from the target branch, and record one `Version impact`: `none`, `patch`, `minor`, or `major`.

For a version change, run `scripts/Bump-Version.ps1` once from the current target version. If the base or scope changes, recompute the intended successor instead of stacking another bump.

Release automation publishes the version already present on `main`. See `docs/RELEASING.md`.

## Compatibility and third-party material

Server-side service and path identifiers are deployed ABI. Check existing installations and uninstall behavior before changing them.

The Go MCP SDK is MIT-licensed and pinned in `go.mod`/`go.sum`; the optional Cloudflare Worker dependencies remain pinned by `package-lock.json`. Preserve license and notice files for vendored material. The QR generator retains its MIT notice under `client/vendor/`; RST itself remains AGPL-3.0-only.
