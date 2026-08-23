// Package serverassets exposes the audited remote Bash payloads embedded in
// the Route Steward executable. The Bash files remain the canonical remote
// implementation and are never downloaded at runtime.
package serverassets

import "embed"

// Files contains every remote script and system configuration template.
//
//go:embed *.sh config/*
var Files embed.FS
