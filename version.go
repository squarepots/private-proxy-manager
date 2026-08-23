package routesteward

import (
	_ "embed"
	"strings"
)

//go:embed version.txt
var versionText string

// Version returns the product version stored in the repository's single
// version authority.
func Version() string {
	return strings.TrimSpace(versionText)
}
