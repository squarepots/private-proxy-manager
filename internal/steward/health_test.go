package steward

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDirectAndRelayHealthUseRealClientEvidenceModel(t *testing.T) {
	for _, kind := range []string{"direct", "relay"} {
		t.Run(kind, func(t *testing.T) {
			state, route := healthFixture(t, kind, true)
			exit := findServer(state.Inventory, route.ExitServer)
			dependencies := healthyHealthDependencies(exit.Network.ExpectedEgressIPv4, deref(exit.Network.ExpectedEgressIPv6), kind == "relay")
			result, err := healthRouteWith(context.Background(), state, route.ID, false, dependencies)
			if err != nil {
				t.Fatal(err)
			}
			if result.Status != "healthy" || result.LatencyMS == nil || *result.LatencyMS != 82 {
				t.Fatalf("healthy %s Route was not healthy: %#v", kind, result)
			}
			if result.PublicIPv4 != nil || result.PublicIPv6 != nil {
				t.Fatal("health exposed a public IP without explicit disclosure")
			}
			if !strings.Contains(result.Summary, "82 ms") {
				t.Fatalf("plain-language summary omitted latency: %q", result.Summary)
			}
			if checkStatus(result, "packet_loss") != "unsupported" || checkStatus(result, "ipv6") != "healthy" {
				t.Fatal("health did not distinguish IPv6 support from unsupported packet loss")
			}
			wantWireGuard := "unsupported"
			if kind == "relay" {
				wantWireGuard = "healthy"
			}
			if checkStatus(result, "wireguard") != wantWireGuard {
				t.Fatalf("%s WireGuard result is wrong", kind)
			}
			observed, err := ReadObserved(state.PrivateDir, false)
			if err != nil || len(observed.Routes) != 1 || observed.Routes[0].Health == nil || observed.Routes[0].Health.Status != "healthy" {
				t.Fatalf("bounded health evidence was not stored: %#v err=%v", observed, err)
			}
			encoded, _ := json.Marshal(result)
			if strings.Contains(string(encoded), exit.Network.ExpectedEgressIPv4) || strings.Contains(string(encoded), deref(exit.Network.ExpectedEgressIPv6)) {
				t.Fatal("sanitized health result leaked an observed public IP")
			}
		})
	}
}

func TestHealthPublicIPRequiresExplicitRequest(t *testing.T) {
	state, route := healthFixture(t, "direct", true)
	exit := findServer(state.Inventory, route.ExitServer)
	result, err := healthRouteWith(context.Background(), state, route.ID, true, healthyHealthDependencies(exit.Network.ExpectedEgressIPv4, deref(exit.Network.ExpectedEgressIPv6), false))
	if err != nil {
		t.Fatal(err)
	}
	if deref(result.PublicIPv4) != exit.Network.ExpectedEgressIPv4 || deref(result.PublicIPv6) != deref(exit.Network.ExpectedEgressIPv6) {
		t.Fatal("explicit public IP disclosure did not return the observed exit")
	}
}

func TestHealthClassifiesDegradedUnhealthyAndUndetermined(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	exit := findServer(state.Inventory, route.ExitServer)
	healthyProbe := healthyHealthDependencies(exit.Network.ExpectedEgressIPv4, "", false)

	degraded := healthyProbe
	degraded.Audit = func(context.Context, *State, string) AuditEvidence {
		return AuditEvidence{Route: route.ID, Status: "undetermined", Category: "undetermined"}
	}
	result, err := healthRouteWith(context.Background(), state, route.ID, false, degraded)
	if err != nil || result.Status != "degraded" {
		t.Fatalf("usable traffic with an undetermined server audit was not degraded: %#v err=%v", result, err)
	}

	unhealthy := healthyProbe
	unhealthy.ProbeNode = func(context.Context, string, *State, routeNode, bool, healthEndpoints) nodeHealthProbe {
		return nodeHealthProbe{IngressFamily: "ipv4", Handshake: "unhealthy", Internet: "unhealthy", DNS: "unhealthy", IPv4: "unhealthy", IPv6: "unsupported"}
	}
	result, err = healthRouteWith(context.Background(), state, route.ID, false, unhealthy)
	if err != nil || result.Status != "unhealthy" {
		t.Fatalf("failed client traffic was not unhealthy: %#v err=%v", result, err)
	}

	undetermined := healthyProbe
	undetermined.EnsureClient = func(context.Context, *State) (string, bool, error) {
		return "", false, errors.New("offline")
	}
	result, err = healthRouteWith(context.Background(), state, route.ID, false, undetermined)
	if err != nil || result.Status != "undetermined" || checkStatus(result, "local_client") != "undetermined" {
		t.Fatalf("unavailable local helper was not undetermined: %#v err=%v", result, err)
	}
}

func TestHealthPreflightRequiresDeployedRouteAndTypedDisclosure(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	ready, err := NewPreflight("health", route.ID, state, map[string]any{"include_public_ip": false}, false)
	if err != nil || !ready.Ready || ready.Mutation || ready.AuthorizationClass != "read-only" {
		t.Fatalf("valid read-only health preflight failed: %#v err=%v", ready, err)
	}
	invalid, err := NewPreflight("health", route.ID, state, map[string]any{"include_public_ip": "yes"}, false)
	if err != nil || invalid.Ready || !contains(invalid.Conflicts, "include-public-ip-must-be-boolean") {
		t.Fatal("invalid public IP disclosure context was accepted")
	}
	findRoute(state.Inventory, route.ID).State = "planned"
	if err := state.Save(false); err != nil {
		t.Fatal(err)
	}
	planned, err := NewPreflight("health", route.ID, state, nil, false)
	if err != nil || planned.Ready || !contains(planned.Conflicts, "target-route-not-deployed") {
		t.Fatal("health accepted a Route that has not been deployed")
	}
}

func TestHysteriaHealthConfigUsesPinnedTLSAndLoopbackHTTP(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	nodes, err := healthRouteNodes(state, route)
	if err != nil || len(nodes) != 1 {
		t.Fatalf("health nodes failed: %v", err)
	}
	config, err := hysteriaHealthConfig(nodes[0], "127.0.0.1:12345")
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(config, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["server"] != "192.0.2.10:443" || decoded["auth"] == "" {
		t.Fatal("health config omitted canonical Route connection values")
	}
	tls := decoded["tls"].(map[string]any)
	if tls["insecure"] != true || len(tls["pinSHA256"].(string)) != 64 {
		t.Fatal("health config did not pair insecure self-signed TLS with the canonical certificate pin")
	}
	httpMode := decoded["http"].(map[string]any)
	if httpMode["listen"] != "127.0.0.1:12345" {
		t.Fatal("health proxy did not stay on loopback")
	}
}

func TestFetchHealthTraceIsBoundedAndRequiresAnIP(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path == "/missing" {
			_, _ = response.Write([]byte("colo=SJC\n"))
			return
		}
		_, _ = response.Write([]byte("ip=198.51.100.20\ncolo=SJC\n"))
	}))
	defer server.Close()
	trace, _, err := fetchHealthTrace(context.Background(), server.Client(), server.URL+"/trace")
	if err != nil || trace["ip"] != "198.51.100.20" {
		t.Fatalf("valid trace was rejected: %#v err=%v", trace, err)
	}
	if _, _, err := fetchHealthTrace(context.Background(), server.Client(), server.URL+"/missing"); err == nil {
		t.Fatal("trace without an IP address was accepted")
	}
}

func healthyHealthDependencies(ipv4, ipv6 string, relay bool) healthDependencies {
	wireGuard := (*string)(nil)
	if relay {
		value := "fixture-wireguard"
		wireGuard = &value
	}
	return healthDependencies{
		Audit: func(context.Context, *State, string) AuditEvidence {
			return AuditEvidence{Status: "healthy", Category: "in-sync", ActualEgressIPv4: stringPointer(ipv4), EgressMatchesDeclaredExit: true, HysteriaVersion: stringPointer("v2.9.3"), WireGuardVersion: wireGuard}
		},
		EnsureClient: func(context.Context, *State) (string, bool, error) { return "fixture-hysteria", false, nil },
		ProbeNode: func(_ context.Context, _ string, _ *State, node routeNode, testIPv6 bool, _ healthEndpoints) nodeHealthProbe {
			latency := int64(82)
			probe := nodeHealthProbe{IngressFamily: addressFamily(node.Values["server"]), Handshake: "healthy", Internet: "healthy", DNS: "healthy", IPv4: "healthy", IPv6: "unsupported", ActualIPv4: ipv4, LatencyMS: &latency}
			if testIPv6 {
				probe.IPv6, probe.ActualIPv6 = "healthy", ipv6
			}
			return probe
		},
		Now:       func() time.Time { return time.Date(2026, 8, 24, 10, 0, 0, 0, time.UTC) },
		Endpoints: healthEndpoints{IPv4: "https://ipv4.example.invalid", IPv6: "https://ipv6.example.invalid", DNS: "https://dns.example.invalid"},
	}
}

func healthFixture(t *testing.T, kind string, withIPv6 bool) (*State, Route) {
	t.Helper()
	privateDir := filepath.Join(t.TempDir(), "private")
	state, _, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(privateDir, "fixture.pem")
	if err := os.WriteFile(key, []byte("fixture"), 0o600); err != nil {
		t.Fatal(err)
	}
	entryContext := map[string]any{"server_id": "entry-a", "public_ipv4": "192.0.2.10", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}
	if withIPv6 {
		entryContext["public_ipv6"] = "2001:db8::10"
		entryContext["expected_egress_ipv6"] = "2001:db8::10"
	}
	if _, err := AddServer(state, entryContext); err != nil {
		t.Fatal(err)
	}
	routeContext := map[string]any{"route_id": "route-a", "display_name": "Route-A", "kind": kind, "entry_server": "entry-a", "listen_port": 443}
	if kind == "relay" {
		exitContext := map[string]any{"server_id": "exit-b", "public_ipv4": "198.51.100.20", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"}
		if withIPv6 {
			exitContext["public_ipv6"] = "2001:db8::20"
			exitContext["expected_egress_ipv6"] = "2001:db8::20"
		}
		if _, err := AddServer(state, exitContext); err != nil {
			t.Fatal(err)
		}
		if _, err := AddLink(state, map[string]any{"link_id": "link-a", "entry_server": "entry-a", "exit_server": "exit-b"}); err != nil {
			t.Fatal(err)
		}
		routeContext["exit_server"] = "exit-b"
		routeContext["link_id"] = "link-a"
	}
	if _, err := AddRoute(state, routeContext); err != nil {
		t.Fatal(err)
	}
	state, err = LoadState(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	route := findRoute(state.Inventory, "route-a")
	route.Enabled, route.State = true, "deployed"
	if err := state.Save(false); err != nil {
		t.Fatal(err)
	}
	return state, *route
}

func checkStatus(result HealthResult, name string) string {
	for _, check := range result.Checks {
		if check.Name == name {
			return check.Status
		}
	}
	return ""
}
