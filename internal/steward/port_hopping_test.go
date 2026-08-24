package steward

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPortHoppingRoutePreservesOneClientContract(t *testing.T) {
	state, _, err := Bootstrap(filepath.Join(t.TempDir(), "private"))
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(state.PrivateDir, "fixture.pem")
	if err := writeFileAtomic(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AddServer(state, map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddRoute(state, map[string]any{"route_id": "hop-a", "display_name": "Hop-A", "kind": "direct", "entry_server": "entry-a", "port_hopping": "20000-20003"}); err != nil {
		t.Fatal(err)
	}
	route := findRoute(state.Inventory, "hop-a")
	if route == nil || route.ListenPort != 20000 || route.PortHopping == nil || route.PortHopping.EndPort != 20003 {
		t.Fatalf("route did not retain canonical port hopping state: %#v", route)
	}
	entry := findServer(state.Inventory, "entry-a")
	if entry == nil || len(entry.Firewall.Rules) < 2 || entry.Firewall.Rules[len(entry.Firewall.Rules)-1].Port != 20000 || entry.Firewall.Rules[len(entry.Firewall.Rules)-1].EndPort != 20003 {
		t.Fatalf("route did not allocate a matching firewall range: %#v", entry)
	}
	payloadPath, err := ResolveSecret(route.PayloadSecretRef, state.PrivateDir, nil)
	if err != nil {
		t.Fatal(err)
	}
	payload, err := os.ReadFile(payloadPath)
	if err != nil {
		t.Fatal(err)
	}
	nodes, _, err := parseRoutePayload(string(payload))
	if err != nil || len(nodes) != 1 {
		t.Fatalf("canonical payload did not parse: nodes=%#v err=%v", nodes, err)
	}
	if nodes[0].Values["ports"] != "20000-20003" {
		t.Fatalf("payload omitted port hopping: %#v", nodes[0].Values)
	}
	uri, err := shadowrocketURI(nodes[0])
	if err != nil || !strings.Contains(uri, "@192.0.2.10:20000-20003/") {
		t.Fatalf("Shadowrocket URI did not use the standard multi-port authority: %q err=%v", uri, err)
	}
	config, err := hysteriaClientConfig(nodes[0], "127.0.0.1:18080", true)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(config, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["server"] != "192.0.2.10:20000-20003" {
		t.Fatalf("headless client did not use a multi-port endpoint: %#v", decoded)
	}
	transport, ok := decoded["transport"].(map[string]any)
	if !ok || transport["type"] != "udp" || transport["udp"].(map[string]any)["hopInterval"] != "30s" {
		t.Fatalf("headless client did not retain the explicit official hopping interval: %#v", decoded)
	}
}

func TestPortHoppingRejectsIncompleteOrOverlappingRanges(t *testing.T) {
	for _, value := range []string{"20000", "20003-20000", "20000-20008", "0-2", "65534-65536"} {
		if _, err := parsePortHoppingRange(value); err == nil {
			t.Fatalf("invalid range %q was accepted", value)
		}
	}
	if err := validatePortHopping(20001, &PortHopping{StartPort: 20000, EndPort: 20003}); err == nil {
		t.Fatal("a range that does not start at listen_port was accepted")
	}
	state, _, err := Bootstrap(filepath.Join(t.TempDir(), "private"))
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(state.PrivateDir, "fixture.pem")
	if err := writeFileAtomic(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, server := range []map[string]any{
		{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"},
		{"server_id": "exit-b", "public_ipv4": "198.51.100.20", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"},
	} {
		if _, err := AddServer(state, server); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := AddRoute(state, map[string]any{"route_id": "hop-a", "display_name": "Hop-A", "kind": "direct", "entry_server": "entry-a", "port_hopping": "20000-20003"}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddLink(state, map[string]any{"link_id": "relay-a", "entry_server": "entry-a", "exit_server": "exit-b"}); err != nil {
		t.Fatal(err)
	}
	_, err = AddRoute(state, map[string]any{"route_id": "hop-b", "display_name": "Hop-B", "kind": "relay", "entry_server": "entry-a", "exit_server": "exit-b", "link_id": "relay-a", "port_hopping": "20003-20005"})
	if err == nil || !strings.Contains(err.Error(), "port-hopping range") {
		t.Fatalf("overlapping range was not rejected before state mutation: %v", err)
	}
}
