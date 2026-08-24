package userjourney_test

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type envelope struct {
	SchemaVersion int             `json:"schema_version"`
	Command       string          `json:"command"`
	Success       bool            `json:"success"`
	Code          string          `json:"code"`
	Data          json.RawMessage `json:"data"`
}

type harness struct {
	t             *testing.T
	binary        string
	privateDir    string
	fakeDir       string
	fakeLog       string
	remotePayload string
	egress        string
}

func TestInstalledCLIUserJourney(t *testing.T) {
	root := repositoryRoot(t)
	temp := t.TempDir()
	binary := testedBinary(t, root, temp)
	fakeBinary := filepath.Join(temp, executable("faketransport"))
	build(t, root, "./tests/faketransport", fakeBinary)
	fakeDir := filepath.Join(temp, "transport")
	if err := os.MkdirAll(fakeDir, 0o700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"ssh", "scp"} {
		copyExecutable(t, fakeBinary, filepath.Join(fakeDir, executable(name)))
	}

	h := &harness{
		t: t, binary: binary, privateDir: filepath.Join(temp, "private"),
		fakeDir: fakeDir, fakeLog: filepath.Join(temp, "transport.log"),
	}
	version := h.plain(0, "version")
	wantVersion := strings.TrimSpace(readFile(t, filepath.Join(root, "version.txt")))
	if strings.TrimSpace(version) != wantVersion {
		t.Fatalf("binary version %q does not match version.txt %q", version, wantVersion)
	}

	capabilities := h.call(0, nil, "capabilities")
	if !capabilities.Success || !bytes.Contains(capabilities.Data, []byte(`"interface":"agent-machine-surface"`)) {
		t.Fatal("installed capabilities did not expose the native machine interface")
	}
	missingState := h.call(1, nil, "context")
	if missingState.Code != "operation-failed" || bytes.Contains(missingState.Data, []byte(h.privateDir)) || !bytes.Contains(missingState.Data, []byte(`"summary"`)) {
		t.Fatal("missing-state failure exposed local diagnostics")
	}
	bootstrap := h.execute(0, "bootstrap", "", nil)
	if !bootstrap.Success {
		t.Fatal("execute bootstrap failed on absent state")
	}
	if repeated := h.call(0, nil, "bootstrap"); !repeated.Success || !bytes.Contains(repeated.Data, []byte(`"created":false`)) {
		t.Fatal("bootstrap was not idempotent")
	}

	key := filepath.Join(h.privateDir, "fixture.pem")
	if err := os.WriteFile(key, []byte("synthetic-key"), 0o600); err != nil {
		t.Fatal(err)
	}
	blocked := h.execute(2, "add-server", "", map[string]any{
		"server_id": "blocked", "public_ipv4": "192.0.2.2", "ssh_user": "bad user", "ssh_key_path": key,
	})
	if blocked.Code != "context-gate-blocked" || fileSize(h.fakeLog) != 0 {
		t.Fatal("invalid server context was not rejected before transport")
	}

	h.mustExecute("add-server", "", map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "public_ipv6": "2001:db8::10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"})
	h.mustExecute("add-server", "", map[string]any{"server_id": "exit-b", "public_ipv4": "198.51.100.20", "ssh_user": "root", "ssh_key_path": key, "host_ownership": "dedicated"})
	h.mustExecute("add-server", "", map[string]any{"server_id": "replacement-c", "public_ipv4": "203.0.113.30", "ssh_user": "user_1", "ssh_key_path": key, "host_ownership": "dedicated"})
	h.mustExecute("add-link", "", map[string]any{"link_id": "relay-a", "entry_server": "entry-a", "exit_server": "exit-b"})
	h.mustExecute("add-route", "", map[string]any{"route_id": "direct-a", "display_name": "Direct-A", "kind": "direct", "entry_server": "entry-a", "listen_port": 443})
	h.mustExecute("add-route", "", map[string]any{"route_id": "relay-route-a", "display_name": "Relay-A", "kind": "relay", "entry_server": "entry-a", "exit_server": "exit-b", "link_id": "relay-a", "listen_port": 8443})

	h.mustExecute("add-provider", "", map[string]any{"provider_id": "optional-a", "url": "https://provider.example.invalid/list.yaml"})
	h.mustExecute("add-provider", "", map[string]any{"provider_id": "spare", "url": "https://spare.example.invalid/list.yaml"})
	h.mustExecute("update-provider", "spare", map[string]any{"display_name": "Temporary"})
	h.mustExecute("remove-provider", "spare", nil)
	h.mustExecute("add-profile", "", map[string]any{"profile_id": "primary", "policy": "privacy", "include_routes": []any{"*"}, "include_providers": []any{"optional-a"}})
	h.mustExecute("add-profile", "", map[string]any{"profile_id": "temporary", "policy": "privacy"})
	h.mustExecute("update-profile", "temporary", map[string]any{"include_routes": []any{"direct-a"}})

	h.mustExecute("add-client-target", "", map[string]any{"target_id": "desktop", "profile_id": "primary", "renderer": "mihomo"})
	h.mustExecute("add-client-target", "", map[string]any{"target_id": "mobile", "profile_id": "primary", "renderer": "shadowrocket", "delivery": "nodes"})
	h.mustExecute("add-client-target", "", map[string]any{"target_id": "temporary", "profile_id": "temporary", "renderer": "shadowrocket"})
	h.mustExecute("update-client-target", "temporary", map[string]any{"profile_id": "primary"})
	h.mustExecute("remove-client-target", "temporary", nil)
	h.mustExecute("remove-profile", "temporary", nil)

	contextResult := h.call(0, nil, "context")
	for _, secret := range []string{"192.0.2.10", "198.51.100.20", key, "provider.example.invalid"} {
		if bytes.Contains(contextResult.Data, []byte(secret)) {
			t.Fatalf("sanitized context exposed %q", secret)
		}
	}

	if err := os.Remove(key); err != nil {
		t.Fatal(err)
	}
	_ = os.Remove(h.fakeLog)
	missingKey := h.execute(2, "deploy-route", "direct-a", nil)
	if missingKey.Code != "context-gate-blocked" || fileSize(h.fakeLog) != 0 {
		t.Fatal("missing SSH key did not stop before transport")
	}
	if err := os.WriteFile(key, []byte("synthetic-key"), 0o600); err != nil {
		t.Fatal(err)
	}

	directPayload := filepath.Join(h.privateDir, "secrets", "managed-routes", "direct-a", "client-payload.yaml")
	h.remotePayload = filepath.Join(temp, "remote-direct-payload.yaml")
	writeRemotePayload(t, directPayload, h.remotePayload, "ipv4: '192.0.2.10'\nipv6: '2001:db8::10'\n")
	h.egress = "192.0.2.10"
	h.mustExecute("deploy-route", "direct-a", nil)
	assertFilesEqual(t, directPayload, h.remotePayload)
	relayPayload := filepath.Join(h.privateDir, "secrets", "managed-routes", "relay-route-a", "client-payload.yaml")
	h.remotePayload = filepath.Join(temp, "remote-relay-payload.yaml")
	writeRemotePayload(t, relayPayload, h.remotePayload, "kind: 'relay'\nvia: 'entry-a'\nipv4: '198.51.100.20'\nentry_ipv4: '192.0.2.10'\nentry_ipv6: '2001:db8::10'\n")
	h.egress = "198.51.100.20"
	h.mustExecute("deploy-route", "relay-route-a", nil)
	assertFilesEqual(t, relayPayload, h.remotePayload)
	transportLog := readFile(t, h.fakeLog)
	if !strings.Contains(transportLog, " -l ubuntu 192.0.2.10 ") || !strings.Contains(transportLog, " -o User=ubuntu ") {
		t.Fatal("SSH/SCP did not pass the validated user as a separate transport option")
	}
	for _, combinedTarget := range []string{"ubuntu@", "root@", "user_1@"} {
		if strings.Contains(transportLog, combinedTarget) {
			t.Fatalf("transport rebuilt an unvalidated user@host target: %s", combinedTarget)
		}
	}
	h.mustExecute("render-client", "desktop", nil)
	h.mustExecute("render-client", "mobile", nil)

	for _, artifact := range []string{"desktop.yaml", "mobile.html"} {
		if _, err := os.Stat(filepath.Join(h.privateDir, "delivery", artifact)); err != nil {
			t.Fatalf("rendered artifact %s is missing: %v", artifact, err)
		}
	}
	h.egress = "192.0.2.10"
	audit := h.execute(0, "audit", "direct-a", nil)
	if !bytes.Contains(audit.Data, []byte(`"category":"in-sync"`)) {
		t.Fatal("direct audit did not report in-sync")
	}
	healthPreflight := h.preflight("health", "direct-a", map[string]any{"include_public_ip": false})
	if !bytes.Contains(healthPreflight.Data, []byte(`"ready":true`)) || !bytes.Contains(healthPreflight.Data, []byte(`"authorization_class":"read-only"`)) {
		t.Fatal("deployed Route health did not pass its read-only preflight")
	}
	drift := h.call(0, nil, "drift")
	if !bytes.Contains(drift.Data, []byte(`"drifted":false`)) {
		t.Fatalf("deployed and rendered state still drifted: %s", drift.Data)
	}

	publication := h.preflight("publish-subscription", "mobile", map[string]any{"worker_name": "synthetic-worker", "host": "subscription.example.invalid"})
	if !bytes.Contains(publication.Data, []byte(`"ready":true`)) {
		t.Fatal("valid subscription publication context did not pass preflight")
	}
	rotation := h.preflight("rotate-subscription-token", "mobile", nil)
	if !bytes.Contains(rotation.Data, []byte(`"ready":false`)) {
		t.Fatal("token rotation without subscription state was not blocked")
	}
	migration := h.execute(4, "migrate-route", "direct-a", map[string]any{"replacement_server_id": "replacement-c"})
	if migration.Code != "workflow-blocked" || !bytes.Contains(migration.Data, []byte(`"next"`)) || !bytes.Contains(migration.Data, []byte(`"old_capacity_retired":false`)) {
		t.Fatal("migration did not preserve overlap-first workflow ownership")
	}
	backup := h.execute(3, "backup", "", nil)
	if backup.Code != "local-assistance-required" || !bytes.Contains(backup.Data, []byte(`"repository_script":"scripts/New-RecoveryArchive.ps1"`)) || !bytes.Contains(backup.Data, []byte(`"secret_prompt_rule"`)) {
		t.Fatal("backup did not stay in the local secret-prompt boundary")
	}
}

func TestMCPStdioUsesInstalledBinary(t *testing.T) {
	root := repositoryRoot(t)
	temp := t.TempDir()
	binary := testedBinary(t, root, temp)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := mcp.NewClient(&mcp.Implementation{Name: "stdio-acceptance", Version: "1"}, nil)
	transport := &mcp.CommandTransport{Command: exec.Command(binary, "mcp", "--private-dir", filepath.Join(temp, "private"))}
	session, err := client.Connect(ctx, transport, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	toolCount := 0
	for _, err := range session.Tools(ctx, nil) {
		if err != nil {
			t.Fatal(err)
		}
		toolCount++
	}
	if toolCount != 9 {
		t.Fatalf("stdio MCP listed %d tools, want 9", toolCount)
	}
	for _, name := range []string{"route_steward_bootstrap", "route_steward_capabilities", "route_steward_context", "route_steward_drift", "route_steward_migrations"} {
		result, err := session.CallTool(ctx, &mcp.CallToolParams{Name: name, Arguments: map[string]any{}})
		if err != nil || result.IsError {
			t.Fatalf("stdio MCP tool %s failed: result=%#v err=%v", name, result, err)
		}
	}
}

func (h *harness) call(expected int, input map[string]any, command string, extra ...string) envelope {
	args := []string{command, "--private-dir", h.privateDir}
	args = append(args, extra...)
	var stdin []byte
	if input != nil {
		args = append(args, "--context-stdin")
		stdin, _ = json.Marshal(input)
	}
	cmd := exec.Command(h.binary, args...)
	cmd.Stdin = bytes.NewReader(stdin)
	cmd.Env = append(os.Environ(),
		"PATH="+h.fakeDir+string(os.PathListSeparator)+os.Getenv("PATH"),
		"RST_FAKE_LOG="+h.fakeLog,
		"RST_FAKE_PAYLOAD="+h.remotePayload,
		"RST_FAKE_EGRESS="+h.egress,
	)
	output, err := cmd.CombinedOutput()
	exit := 0
	if err != nil {
		exitError, ok := err.(*exec.ExitError)
		if !ok {
			h.t.Fatalf("start %s: %v", command, err)
		}
		exit = exitError.ExitCode()
	}
	if exit != expected {
		h.t.Fatalf("%s exited %d, want %d: %s", command, exit, expected, output)
	}
	var result envelope
	if err := json.Unmarshal(output, &result); err != nil {
		h.t.Fatalf("%s returned non-JSON output: %s", command, output)
	}
	return result
}

func (h *harness) execute(expected int, operation, target string, input map[string]any) envelope {
	extra := []string{"--operation", operation}
	if target != "" {
		extra = append(extra, "--target", target)
	}
	return h.call(expected, input, "execute", extra...)
}

func (h *harness) mustExecute(operation, target string, input map[string]any) envelope {
	result := h.execute(0, operation, target, input)
	if !result.Success {
		h.t.Fatalf("%s returned failure: %#v", operation, result)
	}
	return result
}

func (h *harness) preflight(operation, target string, input map[string]any) envelope {
	extra := []string{"--operation", operation}
	if target != "" {
		extra = append(extra, "--target", target)
	}
	return h.call(0, input, "preflight", extra...)
}

func (h *harness) plain(expected int, args ...string) string {
	cmd := exec.Command(h.binary, args...)
	output, err := cmd.CombinedOutput()
	exit := 0
	if err != nil {
		if exitError, ok := err.(*exec.ExitError); ok {
			exit = exitError.ExitCode()
		} else {
			h.t.Fatal(err)
		}
	}
	if exit != expected {
		h.t.Fatalf("%v exited %d, want %d: %s", args, exit, expected, output)
	}
	return string(output)
}

func repositoryRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate acceptance test")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func executable(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

func build(t *testing.T, root, pkg, output string) {
	t.Helper()
	cmd := exec.Command("go", "build", "-trimpath", "-o", output, pkg)
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build %s: %v\n%s", pkg, err, out)
	}
}

func testedBinary(t *testing.T, root, temp string) string {
	t.Helper()
	if candidate := os.Getenv("ROUTE_STEWARD_BINARY"); candidate != "" {
		absolute, err := filepath.Abs(candidate)
		if err != nil {
			t.Fatal(err)
		}
		if info, err := os.Stat(absolute); err != nil || !info.Mode().IsRegular() {
			t.Fatalf("ROUTE_STEWARD_BINARY is not a regular file: %s", absolute)
		}
		return absolute
	}
	binary := filepath.Join(temp, executable("route-steward"))
	build(t, root, "./cmd/route-steward", binary)
	return binary
}

func copyExecutable(t *testing.T, source, target string) {
	t.Helper()
	data, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, data, 0o700); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func fileSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

func writeRemotePayload(t *testing.T, canonical, output, metadata string) {
	t.Helper()
	data, err := os.ReadFile(canonical)
	if err != nil {
		t.Fatal(err)
	}
	text := strings.Replace(string(data), "\nproxies:\n", "\n"+metadata+"proxies:\n", 1)
	lines := strings.Split(text, "\n")
	for i, line := range lines {
		marker := "fingerprint: '"
		index := strings.Index(line, marker)
		if index < 0 {
			continue
		}
		start := index + len(marker)
		end := strings.Index(line[start:], "'")
		if end < 0 {
			t.Fatal("synthetic payload fingerprint is malformed")
		}
		hexValue := strings.ToUpper(strings.NewReplacer(":", "", "-", "", " ", "").Replace(line[start : start+end]))
		pairs := make([]string, 0, len(hexValue)/2)
		for offset := 0; offset < len(hexValue); offset += 2 {
			pairs = append(pairs, hexValue[offset:offset+2])
		}
		lines[i] = line[:start] + strings.Join(pairs, ":") + line[start+end:]
	}
	remote := []byte(strings.Join(lines, "\n"))
	if bytes.Equal(data, remote) {
		t.Fatal("synthetic remote payload did not differ from the local pre-deploy payload")
	}
	if err := os.WriteFile(output, remote, 0o600); err != nil {
		t.Fatal(err)
	}
}

func assertFilesEqual(t *testing.T, left, right string) {
	t.Helper()
	a, err := os.ReadFile(left)
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(right)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a, b) {
		t.Fatal("canonical payload did not adopt the validated server output")
	}
}
