package steward

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestGoControlPlaneLifecycle(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	state, created, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	if !created || state.Inventory.Schema != 1 {
		t.Fatal("bootstrap did not create schema 1 state")
	}
	if len(state.Inventory.Servers) != 0 || len(state.Inventory.Profiles) != 0 || len(state.Inventory.ClientTargets) != 0 {
		t.Fatal("bootstrap made user-specific assumptions")
	}
	if _, createdAgain, err := Bootstrap(privateDir); err != nil || createdAgain {
		t.Fatalf("idempotent bootstrap failed: created=%v err=%v", createdAgain, err)
	}

	badUsers := []string{"-oProxyCommand=bad", "--help", "bad@user", "bad user", "bad\nuser", strings.Repeat("a", 33)}
	for _, badUser := range badUsers {
		preflight, err := NewPreflight("add-server", "", state, map[string]any{"server_id": "blocked", "public_ipv4": "192.0.2.2", "ssh_user": badUser, "ssh_key_path": "fixture", "host_ownership": "dedicated"}, false)
		if err != nil {
			t.Fatal(err)
		}
		if preflight.Ready || !contains(preflight.Conflicts, "ssh-user-invalid") {
			t.Fatalf("unsafe SSH user passed preflight: %q", badUser)
		}
	}
	missingOwnership, err := NewPreflight("add-server", "", state, map[string]any{"server_id": "blocked", "public_ipv4": "192.0.2.2", "ssh_user": "ubuntu", "ssh_key_path": "fixture"}, false)
	if err != nil || missingOwnership.Ready || !contains(missingOwnership.MissingContext, "host-ownership") {
		t.Fatal("dedicated-host confirmation was not required")
	}

	key := filepath.Join(privateDir, "fixture.pem")
	if err := writeFileAtomic(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	add := func(operation, target string, context map[string]any) {
		preflight, err := NewPreflight(operation, target, state, context, false)
		if err != nil {
			t.Fatal(err)
		}
		if !preflight.Ready {
			t.Fatalf("%s preflight blocked: %#v", operation, preflight)
		}
		request := Request{Command: "execute", Operation: operation, Target: target, Context: context, PrivateDir: privateDir}
		envelope, exit := RunRequest(contextBackground(), request)
		if exit != 0 || !envelope.Success {
			t.Fatalf("%s failed: exit=%d %#v", operation, exit, envelope)
		}
		fresh, err := LoadState(privateDir)
		if err != nil {
			t.Fatal(err)
		}
		state = fresh
	}
	add("add-server", "", map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "public_ipv6": "2001:db8::10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"})
	add("add-server", "", map[string]any{"server_id": "exit-b", "public_ipv4": "198.51.100.20", "ssh_user": "root", "ssh_key_path": key, "host_ownership": "dedicated"})
	add("add-link", "", map[string]any{"link_id": "relay-a", "entry_server": "entry-a", "exit_server": "exit-b"})
	add("add-route", "", map[string]any{"route_id": "direct-a", "display_name": "Direct-A", "kind": "direct", "entry_server": "entry-a", "listen_port": 443})
	add("add-route", "", map[string]any{"route_id": "relay-route-a", "display_name": "Relay-A", "kind": "relay", "entry_server": "entry-a", "exit_server": "exit-b", "link_id": "relay-a", "listen_port": 8443})
	add("add-provider", "", map[string]any{"provider_id": "optional-a", "url": "https://provider.example.invalid/list.yaml"})
	providerIndex, err := ReadSecretIndex(privateDir)
	if err != nil || providerIndex.Refs["provider:optional-a"].Type != "url" {
		t.Fatal("Provider secret type changed from the schema-1 contract")
	}
	add("add-profile", "", map[string]any{"profile_id": "primary", "policy": "privacy", "include_routes": []any{"*"}, "include_providers": []any{"optional-a"}})
	add("add-client-target", "", map[string]any{"target_id": "desktop", "profile_id": "primary", "renderer": "mihomo"})
	add("add-client-target", "", map[string]any{"target_id": "mobile", "profile_id": "primary", "renderer": "shadowrocket", "delivery": "nodes"})

	for i := range state.Inventory.Routes {
		state.Inventory.Routes[i].Enabled = true
		state.Inventory.Routes[i].State = "deployed"
	}
	if err := state.Save(false); err != nil {
		t.Fatal(err)
	}
	before, err := DriftReport(state)
	if err != nil {
		t.Fatal(err)
	}
	if !before["drifted"].(bool) {
		t.Fatal("never-audited routes and missing client renders were not drift")
	}
	render, err := RenderClients(state, "", true)
	if err != nil {
		t.Fatal(err)
	}
	if len(render.Outputs) != 2 {
		t.Fatalf("got %d render outputs", len(render.Outputs))
	}
	sanitized := SanitizedRender(render)
	encoded, _ := json.Marshal(sanitized)
	if strings.Contains(string(encoded), privateDir) || strings.Contains(string(encoded), `:\`) {
		t.Fatal("sanitized render leaked an absolute path")
	}
	for _, output := range sanitized.Outputs {
		if output.Path != "" || output.Artifact == nil || !strings.HasPrefix(output.Artifact.RelativePath, "<private>/delivery/") {
			t.Fatal("render did not use sanitized artifact shape")
		}
	}
	if !regularFile(filepath.Join(privateDir, "delivery", "desktop.yaml")) || !regularFile(filepath.Join(privateDir, "delivery", "mobile.html")) {
		t.Fatal("client artifacts were not written")
	}
	for _, route := range state.Inventory.Routes {
		if _, err := SetObservedRoute(state, route.ID, "healthy", "in-sync", findServer(state.Inventory, route.ExitServer).Network.ExpectedEgressIPv4, "v-test", "v-test"); err != nil {
			t.Fatal(err)
		}
	}
	after, err := DriftReport(state)
	if err != nil {
		t.Fatal(err)
	}
	if after["drifted"].(bool) {
		t.Fatalf("healthy routes and current renders reported drift: %#v", after)
	}

	contextValue := SanitizedContext(state.Inventory)
	contextJSON, _ := json.Marshal(contextValue)
	for _, secret := range []string{"192.0.2.10", "198.51.100.20", key, "provider.example.invalid"} {
		if strings.Contains(string(contextJSON), secret) {
			t.Fatalf("sanitized context leaked %q", secret)
		}
	}
	if size, err := AssertSubscriptionBodySize(strings.Repeat("a", 5120)); err != nil || size != 5120 {
		t.Fatal("5120-byte subscription body was rejected")
	}
	if size, err := AssertSubscriptionBodySize(strings.Repeat("é", 2560)); err != nil || size != 5120 {
		t.Fatal("multibyte subscription body was miscounted")
	}
	if _, err := AssertSubscriptionBodySize(strings.Repeat("a", 5121)); err == nil || err.Error() != "subscription-payload-too-large" {
		t.Fatal("oversize subscription body was accepted")
	}
}

func TestRemotePayloadValidationUsesSemantics(t *testing.T) {
	fingerprint := strings.Repeat("ab", 32)
	expected := []byte("schema: 1\nname: 'Entry-A'\nproxies:\n  - name: Entry-A-HY2-v4\n    type: hysteria2\n    server: '192.0.2.10'\n    port: 443\n    password: 'fixture-auth'\n    sni: '192.0.2.10'\n    skip-cert-verify: true\n    fingerprint: '" + fingerprint + "'\n    alpn: [h3]\n    obfs: salamander\n    obfs-password: 'fixture-obfs'\n")
	pairs := make([]string, 0, 32)
	upper := strings.ToUpper(fingerprint)
	for i := 0; i < len(upper); i += 2 {
		pairs = append(pairs, upper[i:i+2])
	}
	actual := []byte("schema: 1\nname: 'Entry-A'\nipv4: '192.0.2.10'\nproxies:\n  - name: Entry-A-HY2-v4\n    type: hysteria2\n    server: '192.0.2.10'\n    port: 443\n    password: 'fixture-auth'\n    sni: '192.0.2.10'\n    skip-cert-verify: true\n    fingerprint: '" + strings.Join(pairs, ":") + "'\n    alpn: [h3]\n    obfs: salamander\n    obfs-password: 'fixture-obfs'\n")
	if err := validatePayloadSemantics(expected, actual); err != nil {
		t.Fatalf("equivalent server payload was rejected: %v", err)
	}
	tampered := []byte(strings.Replace(string(actual), "port: 443", "port: 444", 1))
	if err := validatePayloadSemantics(expected, tampered); err == nil {
		t.Fatal("server payload with changed connection semantics was accepted")
	}
}

func TestMachineFailureDoesNotExposePrivatePaths(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private-path-marker")
	envelope, exit := RunRequest(context.Background(), Request{Command: "context", PrivateDir: privateDir})
	data, _ := json.Marshal(envelope.Data)
	if exit != 1 || envelope.Code != "operation-failed" || strings.Contains(string(data), privateDir) || !strings.Contains(string(data), safeFailureSummary) {
		t.Fatalf("failure boundary returned unsafe diagnostics: %#v", envelope)
	}
	oversize, exit := SanitizedFailure("execute", errSubscriptionPayloadTooLarge)
	if exit != 1 || oversize.Code != "subscription-payload-too-large" {
		t.Fatal("oversize payload lost its stable machine-readable classification")
	}
	state, _, err := Bootstrap(privateDir)
	if err != nil || state == nil {
		t.Fatal(err)
	}
	for _, request := range []Request{
		{Command: "preflight", PrivateDir: privateDir},
		{Command: "execute", Operation: "not-supported", PrivateDir: privateDir},
	} {
		failed, failedExit := RunRequest(context.Background(), request)
		failedData, _ := json.Marshal(failed.Data)
		if failedExit != 1 || failed.Code != "operation-failed" || !strings.Contains(string(failedData), safeFailureSummary) {
			t.Fatalf("established machine failure contract changed: %#v", failed)
		}
	}
}

func TestSchemaOneOptionalDefaultsArePreservedOnFirstRead(t *testing.T) {
	var inventory Inventory
	raw := []byte(`{"schema":1,"links":[{"id":"link-a"}],"routes":[{"id":"route-a"}],"providers":[{"id":"provider-a"}],"profiles":[{"id":"profile-a"}]}`)
	if err := json.Unmarshal(raw, &inventory); err != nil {
		t.Fatal(err)
	}
	if !inventory.Links[0].Enabled || !inventory.Routes[0].Enabled || !inventory.Providers[0].Enabled {
		t.Fatal("missing schema-1 enabled fields no longer default to true")
	}
	if len(inventory.Profiles[0].IncludeRoutes) != 1 || inventory.Profiles[0].IncludeRoutes[0] != "*" {
		t.Fatal("missing schema-1 include_routes no longer defaults to wildcard")
	}
	var explicit Inventory
	if err := json.Unmarshal([]byte(`{"links":[{"enabled":false}],"routes":[{"enabled":false}],"providers":[{"enabled":false}],"profiles":[{"include_routes":[]}]}`), &explicit); err != nil {
		t.Fatal(err)
	}
	if explicit.Links[0].Enabled || explicit.Routes[0].Enabled || explicit.Providers[0].Enabled || explicit.Profiles[0].IncludeRoutes == nil || len(explicit.Profiles[0].IncludeRoutes) != 0 {
		t.Fatal("explicit schema-1 false or empty values were replaced by defaults")
	}
}

func TestObservedCategoryDefaultIsPreserved(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	state, _, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	state.Inventory.Routes = []Route{{ID: "direct-a", Enabled: true}}
	observed := map[string]any{"schema": 1, "routes": []any{map[string]any{"id": "direct-a", "audit_status": "healthy"}}, "servers": []any{}, "links": []any{}}
	if err := writeJSONAtomic(filepath.Join(privateDir, "observed.json"), observed); err != nil {
		t.Fatal(err)
	}
	report, err := DriftReport(state)
	if err != nil {
		t.Fatal(err)
	}
	items := report["items"].([]map[string]any)
	if len(items) != 1 || items[0]["category"] != "in-sync" || report["drifted"].(bool) {
		t.Fatalf("healthy schema-1 observation without category was treated as drift: %#v", report)
	}
}

func TestWindowsMihomoDiscoveryKeepsClashVergeLocations(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows-specific discovery path")
	}
	root := t.TempDir()
	programFiles := filepath.Join(root, "ProgramFiles")
	executable := filepath.Join(programFiles, "Clash Verge", "verge-mihomo.exe")
	if err := os.MkdirAll(filepath.Dir(executable), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(executable, []byte("fixture"), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", filepath.Join(root, "empty-path"))
	t.Setenv("ProgramFiles", programFiles)
	t.Setenv("LOCALAPPDATA", filepath.Join(root, "LocalAppData"))
	if found := findMihomo(); filepath.Clean(found) != filepath.Clean(executable) {
		t.Fatalf("Clash Verge Mihomo was not discovered: %q", found)
	}
}

func TestPublishedSchema1FixtureRemainsUsable(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	fixture, err := os.ReadFile(filepath.Join("..", "..", "examples", "inventory.example.json"))
	if err != nil {
		t.Fatal(err)
	}
	fixture = []byte(strings.ReplaceAll(string(fixture), "<private>", filepath.ToSlash(privateDir)))
	if err := writeFileAtomic(filepath.Join(privateDir, "inventory.json"), fixture, 0o600); err != nil {
		t.Fatal(err)
	}
	index := SecretIndex{Schema: 1, Refs: map[string]SecretRef{
		"link-key:relay-a":          {Type: "managed-link-key", Path: "managed-links/relay-a/keys.json"},
		"route-payload:direct-a":    {Type: "client-payload", Path: "managed-routes/direct-a/client-payload.yaml"},
		"route-credential:direct-a": {Type: "managed-route-credential", Path: "managed-routes/direct-a/credentials.json"},
	}}
	if err := writeJSONAtomic(filepath.Join(privateDir, "secrets", "index.json"), index); err != nil {
		t.Fatal(err)
	}
	for _, relative := range []string{
		"managed-links/relay-a/keys.json",
		"managed-routes/direct-a/client-payload.yaml",
		"managed-routes/direct-a/credentials.json",
	} {
		if err := writeFileAtomic(filepath.Join(privateDir, "secrets", filepath.FromSlash(relative)), []byte("synthetic fixture\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	state, err := LoadState(privateDir)
	if err != nil {
		t.Fatalf("published schema-1 fixture did not load: %v", err)
	}
	if state.Inventory.Schema != 1 || len(state.Inventory.Servers) != 2 || len(state.Inventory.Routes) != 2 || len(state.Inventory.ClientTargets) != 2 {
		t.Fatal("published schema-1 fixture changed shape")
	}
	if err := state.Save(false); err != nil {
		t.Fatalf("published schema-1 fixture could not be saved: %v", err)
	}
	if _, err := LoadState(privateDir); err != nil {
		t.Fatalf("saved schema-1 fixture could not be reloaded: %v", err)
	}
	saved, err := os.ReadFile(state.InventoryPath)
	if err != nil {
		t.Fatal(err)
	}
	if bytesContains(saved, []byte(`"model_version"`)) || !bytesContains(saved, []byte(`"schema": 1`)) {
		t.Fatal("schema-1 fixture gained a second compatibility axis")
	}
}

func TestInventoryValidationKeepsPublicSafetyRules(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	state, _, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(privateDir, "key.pem")
	if err := writeFileAtomic(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AddServer(state, map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}); err != nil {
		t.Fatal(err)
	}
	valid := cloneInventory(state.Inventory)
	tests := []struct {
		name   string
		mutate func(*Inventory)
	}{
		{"firewall source", func(inv *Inventory) { inv.Servers[0].Firewall.Rules[0].Source = "" }},
		{"firewall protocol", func(inv *Inventory) { inv.Servers[0].Firewall.Rules[0].Protocol = "all" }},
		{"ssh key path", func(inv *Inventory) { inv.Servers[0].SSH.KeyPath = "" }},
		{"private IPv4", func(inv *Inventory) { inv.Servers[0].Network.PrivateIPv4 = stringPointer("not-an-ip") }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			candidate := cloneInventory(valid)
			test.mutate(candidate)
			if err := ValidateInventory(candidate, privateDir, true); err == nil {
				t.Fatalf("invalid %s was accepted", test.name)
			}
		})
	}
}

func TestSchemaOneValidationDoesNotAddMigrationRequirements(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	state, _, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(privateDir, "key.pem")
	if err := writeFileAtomic(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AddServer(state, map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}); err != nil {
		t.Fatal(err)
	}
	candidate := cloneInventory(state.Inventory)
	candidate.Metadata.ID = ""
	candidate.Servers[0].OS = ""
	candidate.Servers[0].Architecture = ""
	candidate.Servers[0].Firewall.Rules = nil
	candidate.Servers[0].Network.PublicIPv6 = stringPointer("")
	candidate.Servers[0].Network.ExpectedEgressIPv6 = stringPointer("not-a-schema-one-contract")
	if err := ValidateInventory(candidate, privateDir, true); err != nil {
		t.Fatalf("schema-1 validator added requirements that the published validator did not own: %v", err)
	}
}

func TestRecoveryCoreRejectsTampering(t *testing.T) {
	root := t.TempDir()
	sourcePrivate := filepath.Join(root, "source-private")
	state, _, err := Bootstrap(sourcePrivate)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(sourcePrivate, "key.pem")
	if err := writeFileAtomic(key, []byte("fixture-key"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AddServer(state, map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.50", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}); err != nil {
		t.Fatal(err)
	}
	extracted := filepath.Join(root, "extracted")
	if err := os.MkdirAll(filepath.Join(extracted, "private"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := copyRegularFile(state.InventoryPath, filepath.Join(extracted, "private", "inventory.json")); err != nil {
		t.Fatal(err)
	}
	if err := copyTree(filepath.Join(sourcePrivate, "secrets"), filepath.Join(extracted, "private", "secrets")); err != nil {
		t.Fatal(err)
	}
	if err := copyRegularFile(key, filepath.Join(extracted, "ssh", "entry-a", "key.pem")); err != nil {
		t.Fatal(err)
	}
	metadata := recoveryMetadata{Schema: 1, Product: "route-steward", InventorySchema: 1, RecoveryModel: "agent-native-local-state"}
	if err := writeJSONAtomic(filepath.Join(extracted, "RECOVERY-METADATA.json"), metadata); err != nil {
		t.Fatal(err)
	}
	if err := writeFileAtomic(filepath.Join(extracted, "START-HERE.md"), []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeRecoveryManifest(extracted); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "restored")
	result, err := RestoreExtractedRecovery(extracted, target)
	if err != nil {
		t.Fatal(err)
	}
	if !result["restored"].(bool) || !result["observed_state_reset"].(bool) {
		t.Fatal("recovery result is incomplete")
	}
	restored, err := LoadState(target)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(restored.Inventory.Servers[0].SSH.KeyPath, target) {
		t.Fatal("recovered SSH key path was not rebound")
	}
	if _, err := os.Stat(restored.Inventory.Servers[0].SSH.KeyPath); err != nil {
		t.Fatal("recovered SSH key is missing")
	}
	tampered := filepath.Join(root, "tampered")
	if err := copyTree(extracted, tampered); err != nil {
		t.Fatal(err)
	}
	file, err := os.OpenFile(filepath.Join(tampered, "private", "inventory.json"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = file.WriteString("\n ")
	_ = file.Close()
	tamperedTarget := filepath.Join(root, "tampered-target")
	if _, err := RestoreExtractedRecovery(tampered, tamperedTarget); err == nil {
		t.Fatal("tampered recovery content was accepted")
	}
	if _, err := os.Stat(tamperedTarget); !os.IsNotExist(err) {
		t.Fatal("failed recovery left a partial destination")
	}
}

func TestRecoveryMetadataDoesNotInspectCurrentRepository(t *testing.T) {
	original, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	unrelated := filepath.Join(t.TempDir(), "unrelated-private-checkout")
	if err := os.MkdirAll(filepath.Join(unrelated, ".git"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(unrelated, ".git", "config"), []byte("[remote \"origin\"]\n\turl = https://example.invalid/private-repository\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(unrelated); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(original)
	metadata := newRecoveryMetadata()
	if metadata.Repository != "https://github.com/squarepots/route-steward" || metadata.Commit != "" {
		t.Fatalf("recovery metadata inherited unrelated current-directory provenance: %#v", metadata)
	}
}

func TestInProcessMCPUsesGoEngine(t *testing.T) {
	privateDir := filepath.Join(t.TempDir(), "private")
	server := NewMCPServer(privateDir)
	client := mcp.NewClient(&mcp.Implementation{Name: "test-client", Version: "1"}, nil)
	serverTransport, clientTransport := mcp.NewInMemoryTransports()
	ctx := context.Background()
	serverSession, err := server.Connect(ctx, serverTransport, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer serverSession.Close()
	clientSession, err := client.Connect(ctx, clientTransport, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer clientSession.Close()
	tools := map[string]*mcp.Tool{}
	for tool, err := range clientSession.Tools(ctx, nil) {
		if err != nil {
			t.Fatal(err)
		}
		tools[tool.Name] = tool
	}
	if len(tools) != 7 {
		t.Fatalf("got %d MCP tools, want 7", len(tools))
	}
	assertAnnotations := func(name string, readOnly, idempotent, openWorld bool) {
		t.Helper()
		annotations := tools[name].Annotations
		if annotations == nil || annotations.ReadOnlyHint != readOnly || annotations.IdempotentHint != idempotent || annotations.DestructiveHint == nil || *annotations.DestructiveHint || annotations.OpenWorldHint == nil || *annotations.OpenWorldHint != openWorld {
			t.Fatalf("MCP tool %s has incorrect safety annotations: %#v", name, annotations)
		}
	}
	for _, name := range []string{"route_steward_capabilities", "route_steward_context", "route_steward_drift", "route_steward_preflight"} {
		assertAnnotations(name, true, true, false)
	}
	assertAnnotations("route_steward_health", true, true, true)
	assertAnnotations("route_steward_bootstrap", false, true, false)
	assertAnnotations("route_steward_execute", false, false, true)
	assertOperationEnum := func(name string, expected []string) {
		t.Helper()
		schema, ok := tools[name].InputSchema.(map[string]any)
		if !ok {
			t.Fatalf("MCP tool %s did not expose an object input schema: %#v", name, tools[name].InputSchema)
		}
		properties, ok := schema["properties"].(map[string]any)
		if !ok {
			t.Fatalf("MCP tool %s has no schema properties", name)
		}
		operation, ok := properties["operation"].(map[string]any)
		if !ok {
			t.Fatalf("MCP tool %s has no operation schema", name)
		}
		rawEnum, ok := operation["enum"].([]any)
		if !ok {
			t.Fatalf("MCP tool %s operation is not an enum", name)
		}
		actual := make([]string, 0, len(rawEnum))
		for _, value := range rawEnum {
			actual = append(actual, value.(string))
		}
		if !reflect.DeepEqual(actual, expected) {
			t.Fatalf("MCP tool %s operation enum changed: got %v want %v", name, actual, expected)
		}
	}
	assertOperationEnum("route_steward_preflight", []string{"status", "audit", "health", "add-server", "add-link", "add-route", "add-provider", "update-provider", "remove-provider", "add-profile", "update-profile", "remove-profile", "add-client-target", "update-client-target", "remove-client-target", "deploy-route", "render-client", "publish-subscription", "rotate-subscription-token", "backup", "migrate-route"})
	assertOperationEnum("route_steward_execute", []string{"status", "audit", "health", "add-server", "add-link", "add-route", "add-provider", "update-provider", "remove-provider", "add-profile", "update-profile", "remove-profile", "add-client-target", "update-client-target", "remove-client-target", "deploy-route", "render-client", "publish-subscription"})
	bootstrap, err := clientSession.CallTool(ctx, &mcp.CallToolParams{Name: "route_steward_bootstrap", Arguments: map[string]any{}})
	if err != nil || bootstrap.IsError {
		t.Fatalf("MCP bootstrap failed: result=%#v err=%v", bootstrap, err)
	}
	capabilities, err := clientSession.CallTool(ctx, &mcp.CallToolParams{Name: "route_steward_capabilities", Arguments: map[string]any{}})
	if err != nil || capabilities.IsError {
		t.Fatalf("MCP capabilities failed: result=%#v err=%v", capabilities, err)
	}
	text := capabilities.Content[0].(*mcp.TextContent).Text
	if !strings.Contains(text, `"product":"route-steward"`) || strings.Contains(text, "pwsh") {
		t.Fatal("MCP did not return the native Go capability surface")
	}
}

func contextBackground() context.Context { return context.Background() }

func bytesContains(value, fragment []byte) bool {
	return strings.Contains(string(value), string(fragment))
}
