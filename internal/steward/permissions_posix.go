//go:build !windows

package steward

import "os"

func protectPath(path string, directory bool) error {
	mode := os.FileMode(0o600)
	if directory {
		mode = 0o700
	}
	return os.Chmod(path, mode)
}

func atomicReplace(source, target string) error { return os.Rename(source, target) }
