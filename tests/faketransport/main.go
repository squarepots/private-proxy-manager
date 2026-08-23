// Command faketransport is a deterministic SSH/SCP boundary used only by
// installed-CLI acceptance tests. It does not simulate a real Ubuntu host.
package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func main() {
	name := strings.TrimSuffix(strings.ToLower(filepath.Base(os.Args[0])), ".exe")
	appendLog(name + " " + strings.Join(os.Args[1:], " "))
	switch name {
	case "ssh":
		fakeSSH()
	case "scp":
		if err := fakeSCP(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintln(os.Stderr, "faketransport must be named ssh or scp")
		os.Exit(2)
	}
}

func appendLog(line string) {
	path := os.Getenv("RST_FAKE_LOG")
	if path == "" {
		return
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = fmt.Fprintln(file, line)
}

func fakeSSH() {
	remote := ""
	if len(os.Args) > 1 {
		remote = os.Args[len(os.Args)-1]
	}
	if strings.Contains(remote, "prepare-relay.sh") {
		fmt.Println("PUBLIC_KEY=" + base64.StdEncoding.EncodeToString(make([]byte, 32)))
		return
	}
	if strings.Contains(remote, "audit-relay.sh") {
		fmt.Println("RST_AUDIT_CATEGORY=in-sync")
		fmt.Println("RELAY_EGRESS_IPV4=" + os.Getenv("RST_FAKE_EGRESS"))
		fmt.Println("HYSTERIA_VERSION=fixture")
		fmt.Println("WIREGUARD_VERSION=fixture")
		fmt.Println("RELAY_ENTRY_AUDIT_OK=1")
		return
	}
	if strings.Contains(remote, "/audit.sh") {
		fmt.Println("RST_AUDIT_CATEGORY=in-sync")
		fmt.Println("IPV4=" + os.Getenv("RST_FAKE_EGRESS"))
		fmt.Println("HYSTERIA_VERSION=fixture")
		fmt.Println("AUDIT_OK=1")
	}
}

func fakeSCP() error {
	args := os.Args[1:]
	if len(args) == 0 {
		return nil
	}
	remoteDownload := false
	for _, arg := range args[:len(args)-1] {
		if strings.Contains(arg, ":/tmp/") {
			remoteDownload = true
			break
		}
	}
	if !remoteDownload {
		return nil
	}
	payload := os.Getenv("RST_FAKE_PAYLOAD")
	if payload == "" {
		return fmt.Errorf("RST_FAKE_PAYLOAD is required for a simulated remote download")
	}
	data, err := os.ReadFile(payload)
	if err != nil {
		return err
	}
	destination := args[len(args)-1]
	if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
		return err
	}
	return os.WriteFile(destination, data, 0o600)
}
