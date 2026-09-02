package steward

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestKaringClientTargetRendersDeterministicPinnedClashImport(t *testing.T) {
	state, route := healthFixture(t, "direct", true)
	if _, err := AddProfile(state, map[string]any{"profile_id": "cross-platform", "include_routes": []any{route.ID}}); err != nil {
		t.Fatal(err)
	}
	context := map[string]any{"target_id": "karing-mobile", "profile_id": "cross-platform", "renderer": "karing"}
	preflight, err := NewPreflight("add-client-target", "", state, context, false)
	if err != nil || !preflight.Ready {
		t.Fatalf("valid Karing target failed preflight: %#v err=%v", preflight, err)
	}
	if _, err := AddClientTarget(state, context); err != nil {
		t.Fatal(err)
	}
	first, err := RenderClients(state, "karing-mobile", true)
	if err != nil || len(first.Outputs) != 1 || first.Outputs[0].Renderer != "karing" || first.Outputs[0].NodeCount != 2 {
		t.Fatalf("Karing render failed: %#v err=%v", first, err)
	}
	path := filepath.Join(state.PrivateDir, "delivery", "karing-mobile.yaml")
	one, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(one), "skip-cert-verify: true") || !strings.Contains(string(one), "fingerprint: '") || !strings.Contains(string(one), "obfs: salamander") {
		t.Fatal("Karing import artifact weakened or omitted the supported Hysteria2 TLS/obfuscation contract")
	}
	for _, forbidden := range []string{"\ntun:", "auto-route:", "strict-route:", "auto-detect-interface:", "dns-hijack:", "listen: 0.0.0.0:1053"} {
		if strings.Contains(string(one), forbidden) {
			t.Fatalf("Karing import artifact retained client-runtime ownership %q", forbidden)
		}
	}
	if _, err := RenderClients(state, "karing-mobile", true); err != nil {
		t.Fatal(err)
	}
	two, err := os.ReadFile(path)
	if err != nil || string(one) != string(two) {
		t.Fatalf("Karing import artifact is not deterministic: err=%v", err)
	}
}

func TestKaringClientTargetRejectsMissingCertificatePin(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	if _, err := AddProfile(state, map[string]any{"profile_id": "karing", "include_routes": []any{route.ID}}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddClientTarget(state, map[string]any{"target_id": "karing", "profile_id": "karing", "renderer": "karing"}); err != nil {
		t.Fatal(err)
	}
	payloadPath, err := ResolveSecret(route.PayloadSecretRef, state.PrivateDir, nil)
	if err != nil {
		t.Fatal(err)
	}
	payload, err := os.ReadFile(payloadPath)
	if err != nil {
		t.Fatal(err)
	}
	lines := []string{}
	for _, line := range strings.Split(string(payload), "\n") {
		if !strings.Contains(line, "fingerprint:") {
			lines = append(lines, line)
		}
	}
	if err := os.WriteFile(payloadPath, []byte(strings.Join(lines, "\n")), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := RenderClients(state, "karing", true); err == nil || !strings.Contains(err.Error(), "pinned Hysteria2 import contract") {
		t.Fatalf("Karing renderer accepted a node without certificate pinning: %v", err)
	}
}
