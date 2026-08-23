//go:build windows

package steward

import (
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"syscall"
	"unsafe"
)

var (
	modkernel32     = syscall.NewLazyDLL("kernel32.dll")
	procMoveFileExW = modkernel32.NewProc("MoveFileExW")
)

const moveFileReplaceExisting = 0x1

func protectPath(path string, directory bool) error {
	current, err := user.Current()
	if err != nil {
		return fmt.Errorf("resolve current Windows user: %w", err)
	}
	grant := current.Username + ":(F)"
	if directory {
		grant = current.Username + ":(OI)(CI)(F)"
	}
	cmd := exec.Command("icacls.exe", path, "/inheritance:r", "/grant:r", grant)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("protect private path: %w: %s", err, string(output))
	}
	return nil
}

func atomicReplace(source, target string) error {
	src, err := syscall.UTF16PtrFromString(source)
	if err != nil {
		return err
	}
	dst, err := syscall.UTF16PtrFromString(target)
	if err != nil {
		return err
	}
	r1, _, callErr := procMoveFileExW.Call(uintptr(unsafe.Pointer(src)), uintptr(unsafe.Pointer(dst)), moveFileReplaceExisting)
	if r1 == 0 {
		if callErr != syscall.Errno(0) {
			return callErr
		}
		return os.ErrInvalid
	}
	return nil
}
