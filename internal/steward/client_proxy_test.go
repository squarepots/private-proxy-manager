package steward

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
)

func TestHysteria2ClientTargetRendersOfficialLoopbackConfig(t *testing.T) {
	state, route := healthFixture(t, "direct", true)
	if _, err := AddProfile(state, map[string]any{"profile_id": "backend", "include_routes": []any{route.ID}}); err != nil {
		t.Fatal(err)
	}
	context := map[string]any{"target_id": "service-a", "profile_id": "backend", "renderer": "hysteria2", "route_id": route.ID, "listen": "127.0.0.1:18080", "ingress_family": "auto"}
	preflight, err := NewPreflight("add-client-target", "", state, context, false)
	if err != nil || !preflight.Ready {
		t.Fatalf("valid headless target preflight failed: %#v err=%v", preflight, err)
	}
	if _, err := AddClientTarget(state, context); err != nil {
		t.Fatal(err)
	}
	target := findClientTarget(state.Inventory, "service-a")
	if target == nil || target.Route != route.ID || target.Listen != "127.0.0.1:18080" || target.IngressFamily != "auto" {
		t.Fatalf("headless target state is incomplete: %#v", target)
	}
	unsafeUpdate, err := NewPreflight("update-client-target", target.ID, state, map[string]any{"listen": "0.0.0.0:1080"}, false)
	if err != nil || unsafeUpdate.Ready || !contains(unsafeUpdate.Conflicts, "headless-listen-not-loopback") {
		t.Fatalf("unsafe headless update passed preflight: %#v err=%v", unsafeUpdate, err)
	}
	rendered, err := RenderClients(state, target.ID, true)
	if err != nil || len(rendered.Outputs) != 1 || rendered.Outputs[0].Renderer != "hysteria2" || rendered.Outputs[0].NodeCount != 1 {
		t.Fatalf("headless render failed: %#v err=%v", rendered, err)
	}
	data, err := os.ReadFile(filepath.Join(state.PrivateDir, "delivery", "service-a.json"))
	if err != nil {
		t.Fatal(err)
	}
	var config map[string]any
	if err := json.Unmarshal(data, &config); err != nil {
		t.Fatal(err)
	}
	if config["server"] != "192.0.2.10:443" || config["auth"] == "" {
		t.Fatal("headless config omitted canonical Route connection values or did not prefer IPv4 in auto mode")
	}
	if config["http"].(map[string]any)["listen"] != "127.0.0.1:18080" || config["socks5"].(map[string]any)["listen"] != "127.0.0.1:18080" {
		t.Fatal("headless HTTP and SOCKS5 modes did not share the configured loopback listener")
	}
	tls := config["tls"].(map[string]any)
	if tls["insecure"] != true || len(tls["pinSHA256"].(string)) != 64 {
		t.Fatal("headless config did not retain pinned self-signed TLS verification")
	}
}

func TestHysteria2ClientTargetRejectsUnsafeOrAmbiguousSelection(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	if _, err := AddProfile(state, map[string]any{"profile_id": "selected", "include_routes": []any{route.ID}}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddProfile(state, map[string]any{"profile_id": "empty", "include_routes": []any{}}); err != nil {
		t.Fatal(err)
	}
	base := map[string]any{"target_id": "service-a", "profile_id": "selected", "renderer": "hysteria2", "route_id": route.ID}
	unsafe := cloneContext(base)
	unsafe["listen"] = "0.0.0.0:1080"
	preflight, err := NewPreflight("add-client-target", "", state, unsafe, false)
	if err != nil || preflight.Ready || !contains(preflight.Conflicts, "headless-listen-not-loopback") {
		t.Fatalf("public proxy listener passed preflight: %#v err=%v", preflight, err)
	}
	outside := cloneContext(base)
	outside["profile_id"] = "empty"
	preflight, err = NewPreflight("add-client-target", "", state, outside, false)
	if err != nil || preflight.Ready || !contains(preflight.Conflicts, "headless-route-outside-profile") {
		t.Fatalf("Route outside the Profile passed preflight: %#v err=%v", preflight, err)
	}
	badFamily := cloneContext(base)
	badFamily["ingress_family"] = "either"
	preflight, err = NewPreflight("add-client-target", "", state, badFamily, false)
	if err != nil || preflight.Ready || !contains(preflight.Conflicts, "headless-ingress-family-unsupported") {
		t.Fatalf("unsupported ingress family passed preflight: %#v err=%v", preflight, err)
	}
	wrongRenderer := map[string]any{"target_id": "desktop", "profile_id": "selected", "renderer": "mihomo", "route_id": route.ID}
	preflight, err = NewPreflight("add-client-target", "", state, wrongRenderer, false)
	if err != nil || preflight.Ready || !contains(preflight.Conflicts, "headless-fields-require-hysteria2-renderer") {
		t.Fatalf("headless-only fields passed for a GUI renderer: %#v err=%v", preflight, err)
	}
	for _, value := range []string{"localhost:1080", "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1"} {
		if _, err := normalizeProxyListen(value); err == nil {
			t.Fatalf("unsafe listener %q was accepted", value)
		}
	}
	if got, err := normalizeProxyListen("[::1]:1080"); err != nil || got != "[::1]:1080" {
		t.Fatalf("IPv6 loopback listener was rejected: %q err=%v", got, err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	if err := ensureProxyListenerAvailable(listener.Addr().String()); err == nil {
		t.Fatal("proxy check accepted a listener already owned by another process")
	}
}

func cloneContext(source map[string]any) map[string]any {
	out := make(map[string]any, len(source))
	for key, value := range source {
		out[key] = value
	}
	return out
}
