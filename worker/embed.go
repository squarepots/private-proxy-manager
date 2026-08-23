// Package workerassets exposes the optional Cloudflare delivery Worker so a
// release binary can stage the audited source without a repository checkout.
package workerassets

import "embed"

// Files contains the pinned Worker source and package metadata.
//
//go:embed src/* package.json package-lock.json wrangler.jsonc tsconfig.json
var Files embed.FS
