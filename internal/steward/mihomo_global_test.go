package steward

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestMihomoGlobalSelectorIncludesManagedAndProviderSources(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	if _, err := AddProvider(state, map[string]any{"provider_id": "optional-a", "url": "https://provider.example.invalid/provider.yaml"}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddProfile(state, map[string]any{"profile_id": "primary", "include_routes": []any{route.ID}, "include_providers": []any{"optional-a"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddClientTarget(state, map[string]any{"target_id": "desktop", "profile_id": "primary", "renderer": "mihomo"}); err != nil {
		t.Fatal(err)
	}
	if _, err := RenderClients(state, "desktop", true); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(state.PrivateDir, "delivery", "desktop.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	yaml := string(b)
	for _, fragment := range []string{
		"  - name: GLOBAL\n    type: select\n    proxies:\n      - Private Routes\n      - 'Route-A-HY2-v4'\n      - DIRECT\n      - REJECT\n    use:\n      - 'optional-a'\n",
		"proxy-providers:\n  optional-a:\n",
		"    use:\n      - 'optional-a'\n",
		"  - MATCH,Private Routes\n",
	} {
		if !strings.Contains(yaml, fragment) {
			t.Fatalf("Mihomo global selector output missed %q:\n%s", fragment, yaml)
		}
	}
	if strings.Count(yaml, "  - name: GLOBAL\n") != 1 {
		t.Fatalf("Mihomo output must contain exactly one explicit GLOBAL selector:\n%s", yaml)
	}
	if strings.Count(yaml, "https://provider.example.invalid/provider.yaml") != 1 {
		t.Fatalf("Provider URL was duplicated instead of referenced through the Provider ID:\n%s", yaml)
	}
}

// TestMihomoGlobalCompatibility runs only when CI (or an operator) supplies
// the pinned Mihomo executable through RST_MIHOMO_TEST_BINARY. The product
// never downloads or manages this test dependency.
func TestMihomoGlobalCompatibility(t *testing.T) {
	core := strings.TrimSpace(os.Getenv("RST_MIHOMO_TEST_BINARY"))
	if core == "" {
		t.Skip("set RST_MIHOMO_TEST_BINARY to run the pinned Mihomo compatibility test")
	}
	version, err := exec.Command(core, "-v").CombinedOutput()
	if err != nil || !strings.Contains(string(version), mihomoCompatibilityBaseline) {
		t.Fatalf("compatibility test requires Mihomo %s, got %q: %v", mihomoCompatibilityBaseline, strings.TrimSpace(string(version)), err)
	}

	var refreshed atomic.Bool
	provider := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		response.Header().Set("Content-Type", "application/yaml")
		name := "provider-node"
		if refreshed.Load() {
			name = "provider-node-refreshed"
		}
		_, _ = fmt.Fprintf(response, "proxies:\n  - name: %s\n    type: socks5\n    server: 127.0.0.1\n    port: 9\n", name)
	}))
	defer provider.Close()

	state := mihomoGlobalCompatibilityState(t, provider.URL+"/provider.yaml")
	if _, err := RenderClients(state, "desktop", true); err != nil {
		t.Fatal(err)
	}
	rendered, err := os.ReadFile(filepath.Join(state.PrivateDir, "delivery", "desktop.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	runtimeConfig := strings.Replace(string(rendered), "dns:\n  enable: true\n", "dns:\n  enable: false\n", 1)
	if runtimeConfig == string(rendered) {
		t.Fatal("compatibility fixture could not disable DNS for the isolated core")
	}
	// Mihomo accepts a TCP controller address; use an ephemeral loopback port.
	controller := reserveMihomoControllerAddress(t)
	runtimeConfig = fmt.Sprintf("external-controller: '%s'\n", controller) + runtimeConfig
	configPath := filepath.Join(t.TempDir(), "mihomo.yaml")
	if err := os.WriteFile(configPath, []byte(runtimeConfig), 0o600); err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	command := exec.CommandContext(ctx, core, "-d", t.TempDir(), "-f", configPath)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		cancel()
		if command.Process != nil {
			_ = command.Process.Kill()
		}
		_ = command.Wait()
	}()

	client := &http.Client{Timeout: time.Second}
	api := "http://" + controller
	waitForMihomoGlobalMembers(t, client, api, []string{"Route-A-HY2-v4", "Private Routes", "DIRECT", "REJECT", "provider-node"})
	refreshed.Store(true)
	request, err := http.NewRequest(http.MethodPut, api+"/providers/proxies/optional-a", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	_ = response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("Mihomo provider refresh returned %s", response.Status)
	}
	waitForMihomoGlobalMembers(t, client, api, []string{"provider-node-refreshed"})
}

func mihomoGlobalCompatibilityState(t *testing.T, providerURL string) *State {
	t.Helper()
	state, route := healthFixture(t, "direct", false)
	if _, err := AddProvider(state, map[string]any{"provider_id": "optional-a", "url": providerURL}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddProfile(state, map[string]any{"profile_id": "primary", "include_routes": []any{route.ID}, "include_providers": []any{"optional-a"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddClientTarget(state, map[string]any{"target_id": "desktop", "profile_id": "primary", "renderer": "mihomo"}); err != nil {
		t.Fatal(err)
	}
	return state
}

func waitForMihomoGlobalMembers(t *testing.T, client *http.Client, api string, expected []string) {
	t.Helper()
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		response, err := client.Get(api + "/proxies/GLOBAL")
		if err == nil {
			var payload struct {
				All []string `json:"all"`
			}
			decodeErr := json.NewDecoder(response.Body).Decode(&payload)
			_ = response.Body.Close()
			if response.StatusCode == http.StatusOK && decodeErr == nil {
				members := map[string]bool{}
				for _, member := range payload.All {
					members[member] = true
				}
				complete := true
				for _, member := range expected {
					complete = complete && members[member]
				}
				if complete {
					return
				}
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("Mihomo GLOBAL did not expose %v", expected)
}

func reserveMihomoControllerAddress(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	if err := listener.Close(); err != nil {
		t.Fatal(err)
	}
	return address
}
