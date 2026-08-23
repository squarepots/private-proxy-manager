// Package clientassets exposes the vendored, offline QR renderer used for
// Shadowrocket import pages.
package clientassets

import "embed"

// Files contains the vendored QR implementation and its notices.
//
//go:embed vendor/*
var Files embed.FS
