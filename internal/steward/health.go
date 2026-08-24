package steward

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const healthResponseLimit = 64 << 10

type healthEndpoints struct {
	IPv4 string
	IPv6 string
	DNS  string
}

var defaultHealthEndpoints = healthEndpoints{
	IPv4: "https://api.ipify.org?format=json",
	IPv6: "https://api6.ipify.org?format=json",
	DNS:  "https://cloudflare.com/cdn-cgi/trace",
}

type healthDependencies struct {
	Audit        func(context.Context, *State, string) AuditEvidence
	EnsureClient func(context.Context, *State) (string, bool, error)
	ProbeNode    func(context.Context, string, *State, routeNode, bool, healthEndpoints) nodeHealthProbe
	Now          func() time.Time
	Endpoints    healthEndpoints
}

type nodeHealthProbe struct {
	IngressFamily string
	Handshake     string
	Internet      string
	DNS           string
	IPv4          string
	IPv6          string
	ActualIPv4    string
	ActualIPv6    string
	LatencyMS     *int64
}

func HealthRoute(ctx context.Context, state *State, routeID string, includePublicIP bool) (HealthResult, error) {
	dependencies := healthDependencies{
		Audit:        AuditRoute,
		EnsureClient: ensureHysteriaClient,
		ProbeNode:    probeHysteriaNode,
		Now:          time.Now,
		Endpoints:    defaultHealthEndpoints,
	}
	return healthRouteWith(ctx, state, routeID, includePublicIP, dependencies)
}

func healthRouteWith(ctx context.Context, state *State, routeID string, includePublicIP bool, dependencies healthDependencies) (HealthResult, error) {
	route := findRoute(state.Inventory, routeID)
	if route == nil {
		return HealthResult{}, fmt.Errorf("unknown Route %q", routeID)
	}
	if dependencies.Audit == nil || dependencies.EnsureClient == nil || dependencies.ProbeNode == nil || dependencies.Now == nil {
		return HealthResult{}, errors.New("health dependencies are incomplete")
	}
	if dependencies.Endpoints.IPv4 == "" || dependencies.Endpoints.DNS == "" {
		return HealthResult{}, errors.New("health endpoints are incomplete")
	}

	checkedAt := dependencies.Now().UTC().Format(time.RFC3339Nano)
	audit := dependencies.Audit(ctx, state, route.ID)
	if _, err := SetObservedRoute(state, route.ID, audit.Status, audit.Category, deref(audit.ActualEgressIPv4), deref(audit.HysteriaVersion), deref(audit.WireGuardVersion)); err != nil {
		return HealthResult{}, err
	}
	checks := []HealthCheck{
		serverReachabilityCheck(audit),
		serverAuditCheck(audit),
	}
	if route.Kind == "relay" {
		checks = append(checks, wireGuardHealthCheck(audit))
	} else {
		checks = append(checks, HealthCheck{Name: "wireguard", Status: "unsupported", Detail: "not-used-by-direct-route"})
	}

	nodes, err := healthRouteNodes(state, *route)
	if err != nil {
		return HealthResult{}, err
	}
	binary, _, helperErr := dependencies.EnsureClient(ctx, state)
	if helperErr != nil {
		checks = append(checks,
			HealthCheck{Name: "local_client", Status: "undetermined", Detail: "verified-helper-unavailable"},
			HealthCheck{Name: "hysteria_handshake", Status: "undetermined", Detail: "client-probe-not-run"},
			HealthCheck{Name: "proxy_internet", Status: "undetermined", Detail: "client-probe-not-run"},
			HealthCheck{Name: "dns", Status: "undetermined", Detail: "client-probe-not-run"},
			HealthCheck{Name: "exit_identity", Status: "undetermined", Detail: "client-probe-not-run"},
			HealthCheck{Name: "ipv4", Status: "undetermined", Detail: "client-probe-not-run"},
		)
		exit := findServer(state.Inventory, route.ExitServer)
		if exit != nil && exit.Network.ExpectedEgressIPv6 != nil {
			checks = append(checks, HealthCheck{Name: "ipv6", Status: "undetermined", Detail: "client-probe-not-run"})
		} else {
			checks = append(checks, HealthCheck{Name: "ipv6", Status: "unsupported", Detail: "no-declared-ipv6-exit"})
		}
		checks = append(checks, HealthCheck{Name: "packet_loss", Status: "unsupported", Detail: "no-stable-safe-metric"})
		result := finalizeHealthResult(*route, checkedAt, checks, nil, "", "", includePublicIP)
		if _, err := SetObservedHealth(state, result); err != nil {
			return HealthResult{}, err
		}
		return result, nil
	}
	checks = append(checks, HealthCheck{Name: "local_client", Status: "healthy", Detail: "verified-hysteria-" + hysteriaClientVersion})

	exit := findServer(state.Inventory, route.ExitServer)
	testIPv6 := exit != nil && exit.Network.ExpectedEgressIPv6 != nil
	probes := make([]nodeHealthProbe, 0, len(nodes))
	for _, node := range nodes {
		probes = append(probes, dependencies.ProbeNode(ctx, binary, state, node, testIPv6, dependencies.Endpoints))
	}
	handshakeStatuses, internetStatuses, dnsStatuses := []string{}, []string{}, []string{}
	ipv4Statuses, ipv6Statuses, exitStatuses := []string{}, []string{}, []string{}
	latencies := []int64{}
	actualIPv4, actualIPv6 := "", ""
	for _, probe := range probes {
		handshakeStatuses = append(handshakeStatuses, probe.Handshake)
		internetStatuses = append(internetStatuses, probe.Internet)
		dnsStatuses = append(dnsStatuses, probe.DNS)
		ipv4Statuses = append(ipv4Statuses, probe.IPv4)
		if testIPv6 {
			ipv6Statuses = append(ipv6Statuses, probe.IPv6)
		}
		if probe.LatencyMS != nil {
			latencies = append(latencies, *probe.LatencyMS)
		}
		if actualIPv4 == "" && probe.ActualIPv4 != "" {
			actualIPv4 = probe.ActualIPv4
		}
		if actualIPv6 == "" && probe.ActualIPv6 != "" {
			actualIPv6 = probe.ActualIPv6
		}
		if exit != nil {
			if probe.ActualIPv4 == "" {
				exitStatuses = append(exitStatuses, "undetermined")
			} else if probe.ActualIPv4 == exit.Network.ExpectedEgressIPv4 {
				exitStatuses = append(exitStatuses, "healthy")
			} else {
				exitStatuses = append(exitStatuses, "unhealthy")
			}
			if testIPv6 {
				if probe.ActualIPv6 == "" {
					exitStatuses = append(exitStatuses, "undetermined")
				} else if probe.ActualIPv6 == deref(exit.Network.ExpectedEgressIPv6) {
					exitStatuses = append(exitStatuses, "healthy")
				} else {
					exitStatuses = append(exitStatuses, "unhealthy")
				}
			}
		}
	}
	latency := minimumLatency(latencies)
	checks = append(checks,
		HealthCheck{Name: "hysteria_handshake", Status: aggregateHealthStatus(handshakeStatuses), Detail: "real-client-probe"},
		HealthCheck{Name: "proxy_internet", Status: aggregateHealthStatus(internetStatuses), Detail: "internet-request-through-proxy", LatencyMS: latency},
		HealthCheck{Name: "dns", Status: aggregateHealthStatus(dnsStatuses), Detail: "hostname-request-through-proxy"},
		HealthCheck{Name: "exit_identity", Status: aggregateHealthStatus(exitStatuses), Detail: "compared-with-declared-exit"},
		HealthCheck{Name: "ipv4", Status: aggregateHealthStatus(ipv4Statuses), Detail: "ipv4-request-through-proxy"},
	)
	if testIPv6 {
		checks = append(checks, HealthCheck{Name: "ipv6", Status: aggregateHealthStatus(ipv6Statuses), Detail: "ipv6-request-through-proxy"})
	} else {
		checks = append(checks, HealthCheck{Name: "ipv6", Status: "unsupported", Detail: "no-declared-ipv6-exit"})
	}
	checks = append(checks, HealthCheck{Name: "packet_loss", Status: "unsupported", Detail: "no-stable-safe-metric"})
	result := finalizeHealthResult(*route, checkedAt, checks, latency, actualIPv4, actualIPv6, includePublicIP)
	if _, err := SetObservedHealth(state, result); err != nil {
		return HealthResult{}, err
	}
	return result, nil
}

func healthRouteNodes(state *State, route Route) ([]routeNode, error) {
	path, err := ResolveSecret(route.PayloadSecretRef, state.PrivateDir, nil)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	nodes, _, err := parseRoutePayload(string(data))
	if err != nil {
		return nil, err
	}
	for _, node := range nodes {
		for _, key := range []string{"server", "port", "password", "sni", "fingerprint", "obfs", "obfs-password"} {
			if node.Values[key] == "" {
				return nil, fmt.Errorf("health node %q is missing %q", node.Name, key)
			}
		}
		if node.Values["obfs"] != "salamander" {
			return nil, fmt.Errorf("health node %q uses unsupported obfuscation", node.Name)
		}
	}
	return nodes, nil
}

func probeHysteriaNode(ctx context.Context, binary string, state *State, node routeNode, testIPv6 bool, endpoints healthEndpoints) nodeHealthProbe {
	probe := nodeHealthProbe{IngressFamily: addressFamily(node.Values["server"]), Handshake: "undetermined", Internet: "unhealthy", DNS: "unhealthy", IPv4: "unhealthy", IPv6: "unsupported"}
	proxyURL, stop, status := startHysteriaHealthProxy(ctx, binary, state, node)
	if status != "healthy" {
		probe.Handshake = status
		probe.Internet = status
		probe.DNS = status
		probe.IPv4 = status
		if testIPv6 {
			probe.IPv6 = status
		}
		return probe
	}
	defer stop()
	client, err := healthHTTPClient(proxyURL)
	if err != nil {
		return probe
	}
	if trace, latency, err := fetchHealthTrace(ctx, client, endpoints.IPv4); err == nil {
		probe.Handshake, probe.Internet, probe.IPv4 = "healthy", "healthy", "healthy"
		probe.LatencyMS = &latency
		if ip := trace["ip"]; net.ParseIP(ip) != nil && net.ParseIP(ip).To4() != nil {
			probe.ActualIPv4 = ip
		}
	}
	if trace, latency, err := fetchHealthTrace(ctx, client, endpoints.DNS); err == nil {
		probe.Handshake, probe.Internet, probe.DNS = "healthy", "healthy", "healthy"
		if probe.LatencyMS == nil || latency < *probe.LatencyMS {
			probe.LatencyMS = &latency
		}
		if ip := trace["ip"]; net.ParseIP(ip) != nil {
			if net.ParseIP(ip).To4() != nil && probe.ActualIPv4 == "" {
				probe.ActualIPv4 = ip
			} else if net.ParseIP(ip).To4() == nil && probe.ActualIPv6 == "" {
				probe.ActualIPv6 = ip
			}
		}
	}
	if testIPv6 {
		probe.IPv6 = "unhealthy"
		if trace, latency, err := fetchHealthTrace(ctx, client, endpoints.IPv6); err == nil {
			probe.Handshake, probe.Internet, probe.IPv6 = "healthy", "healthy", "healthy"
			if probe.LatencyMS == nil || latency < *probe.LatencyMS {
				probe.LatencyMS = &latency
			}
			if ip := trace["ip"]; net.ParseIP(ip) != nil && net.ParseIP(ip).To4() == nil {
				probe.ActualIPv6 = ip
			}
		}
	}
	return probe
}

func startHysteriaHealthProxy(ctx context.Context, binary string, state *State, node routeNode) (string, func(), string) {
	listen, err := reserveLoopbackAddress()
	if err != nil {
		return "", func() {}, "undetermined"
	}
	healthRoot := filepath.Join(state.PrivateDir, "health")
	if err := os.MkdirAll(healthRoot, 0o700); err != nil {
		return "", func() {}, "undetermined"
	}
	if err := protectPath(healthRoot, true); err != nil {
		return "", func() {}, "undetermined"
	}
	probeDir, err := os.MkdirTemp(healthRoot, ".probe-")
	if err != nil {
		return "", func() {}, "undetermined"
	}
	_ = os.Chmod(probeDir, 0o700)
	config, err := hysteriaHealthConfig(node, listen)
	if err != nil {
		_ = os.RemoveAll(probeDir)
		return "", func() {}, "undetermined"
	}
	configPath := filepath.Join(probeDir, "client.json")
	if err := os.WriteFile(configPath, config, 0o600); err != nil {
		_ = os.RemoveAll(probeDir)
		return "", func() {}, "undetermined"
	}
	processContext, cancel := context.WithCancel(ctx)
	command := exec.CommandContext(processContext, binary, "client", "--config", configPath, "--disable-update-check", "--log-level", "warn", "--log-format", "json")
	command.Stdout, command.Stderr = io.Discard, io.Discard
	if err := command.Start(); err != nil {
		cancel()
		_ = os.RemoveAll(probeDir)
		return "", func() {}, "undetermined"
	}
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	deadline := time.NewTimer(12 * time.Second)
	ticker := time.NewTicker(100 * time.Millisecond)
	defer deadline.Stop()
	defer ticker.Stop()
	for {
		select {
		case <-done:
			cancel()
			_ = os.RemoveAll(probeDir)
			return "", func() {}, "unhealthy"
		case <-deadline.C:
			cancel()
			_ = command.Process.Kill()
			<-done
			_ = os.RemoveAll(probeDir)
			return "", func() {}, "unhealthy"
		case <-ticker.C:
			connection, dialErr := net.DialTimeout("tcp", listen, 100*time.Millisecond)
			if dialErr != nil {
				continue
			}
			_ = connection.Close()
			var once sync.Once
			stop := func() {
				once.Do(func() {
					cancel()
					_ = command.Process.Kill()
					select {
					case <-done:
					case <-time.After(2 * time.Second):
					}
					_ = os.RemoveAll(probeDir)
				})
			}
			return "http://" + listen, stop, "healthy"
		}
	}
}

func hysteriaHealthConfig(node routeNode, listen string) ([]byte, error) {
	return hysteriaClientConfig(node, listen, false)
}

func hysteriaClientConfig(node routeNode, listen string, includeSOCKS5 bool) ([]byte, error) {
	port, err := strconv.Atoi(node.Values["port"])
	if err != nil || port < 1 || port > 65535 {
		return nil, errors.New("health node port is invalid")
	}
	fingerprint := strings.ToLower(strings.NewReplacer(":", "", "-", "", " ", "").Replace(node.Values["fingerprint"]))
	decoded, err := hex.DecodeString(fingerprint)
	if err != nil || len(decoded) != 32 {
		return nil, errors.New("health node certificate fingerprint is invalid")
	}
	endpointPort := strconv.Itoa(port)
	portHopping, err := nodePortHoppingRange(node)
	if err != nil {
		return nil, err
	}
	if portHopping != "" {
		endpointPort = portHopping
	}
	server := net.JoinHostPort(node.Values["server"], endpointPort)
	config := map[string]any{
		"server": server,
		"auth":   node.Values["password"],
		"tls": map[string]any{
			"sni":       node.Values["sni"],
			"insecure":  true,
			"pinSHA256": fingerprint,
		},
		"obfs": map[string]any{
			"type":       "salamander",
			"salamander": map[string]string{"password": node.Values["obfs-password"]},
		},
		"http": map[string]string{"listen": listen},
	}
	if includeSOCKS5 {
		config["socks5"] = map[string]string{"listen": listen}
	}
	if portHopping != "" {
		config["transport"] = map[string]any{"type": "udp", "udp": map[string]string{"hopInterval": "30s"}}
	}
	return json.MarshalIndent(config, "", "  ")
}

func reserveLoopbackAddress() (string, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	address := listener.Addr().String()
	if err := listener.Close(); err != nil {
		return "", err
	}
	return address, nil
}

func healthHTTPClient(proxyAddress string) (*http.Client, error) {
	parsed, err := url.Parse(proxyAddress)
	if err != nil {
		return nil, err
	}
	transport := &http.Transport{
		Proxy:                 http.ProxyURL(parsed),
		DisableKeepAlives:     true,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
	}
	return &http.Client{Transport: transport, Timeout: 20 * time.Second}, nil
}

func fetchHealthTrace(ctx context.Context, client *http.Client, endpoint string) (map[string]string, int64, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, 0, err
	}
	request.Header.Set("User-Agent", "Route-Steward-Health/1")
	started := time.Now()
	response, err := client.Do(request)
	latency := time.Since(started).Milliseconds()
	if err != nil {
		return nil, 0, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("health endpoint returned status %d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, healthResponseLimit+1))
	if err != nil {
		return nil, 0, err
	}
	if len(body) > healthResponseLimit {
		return nil, 0, errors.New("health endpoint response is too large")
	}
	trace := map[string]string{}
	var jsonTrace map[string]string
	if err := json.Unmarshal(body, &jsonTrace); err == nil {
		for key, value := range jsonTrace {
			trace[key] = strings.TrimSpace(value)
		}
	}
	for _, line := range strings.Split(strings.ReplaceAll(string(body), "\r\n", "\n"), "\n") {
		parts := strings.SplitN(strings.TrimSpace(line), "=", 2)
		if len(parts) == 2 && parts[0] != "" {
			trace[parts[0]] = strings.TrimSpace(parts[1])
		}
	}
	if net.ParseIP(trace["ip"]) == nil {
		return nil, 0, errors.New("health endpoint did not return an IP address")
	}
	return trace, latency, nil
}

func serverReachabilityCheck(audit AuditEvidence) HealthCheck {
	if audit.Status == "undetermined" {
		return HealthCheck{Name: "server_reachability", Status: "undetermined", Detail: "ssh-audit-did-not-complete"}
	}
	return HealthCheck{Name: "server_reachability", Status: "healthy", Detail: "ssh-audit-completed"}
}

func serverAuditCheck(audit AuditEvidence) HealthCheck {
	status := "unhealthy"
	if audit.Category == "in-sync" {
		status = "healthy"
	} else if audit.Category == "undetermined" {
		status = "undetermined"
	}
	return HealthCheck{Name: "server_audit", Status: status, Detail: audit.Category}
}

func wireGuardHealthCheck(audit AuditEvidence) HealthCheck {
	if audit.Category == "wireguard-link-mismatch" {
		return HealthCheck{Name: "wireguard", Status: "unhealthy", Detail: "wireguard-link-mismatch"}
	}
	if audit.Status == "undetermined" || audit.WireGuardVersion == nil {
		return HealthCheck{Name: "wireguard", Status: "undetermined", Detail: "wireguard-state-not-proven"}
	}
	return HealthCheck{Name: "wireguard", Status: "healthy", Detail: "wireguard-state-observed"}
}

func aggregateHealthStatus(values []string) string {
	counts := map[string]int{}
	for _, value := range values {
		counts[value]++
	}
	if len(values) == 0 {
		return "undetermined"
	}
	if counts["healthy"] > 0 || counts["degraded"] > 0 {
		if counts["unhealthy"] > 0 || counts["undetermined"] > 0 || counts["degraded"] > 0 {
			return "degraded"
		}
		return "healthy"
	}
	if counts["unhealthy"] > 0 {
		return "unhealthy"
	}
	if counts["undetermined"] > 0 {
		return "undetermined"
	}
	return "unsupported"
}

func minimumLatency(values []int64) *int64 {
	if len(values) == 0 {
		return nil
	}
	sort.Slice(values, func(i, j int) bool { return values[i] < values[j] })
	value := values[0]
	return &value
}

func finalizeHealthResult(route Route, checkedAt string, checks []HealthCheck, latency *int64, actualIPv4, actualIPv6 string, includePublicIP bool) HealthResult {
	byName := map[string]string{}
	for _, check := range checks {
		byName[check.Name] = check.Status
	}
	core := []string{"local_client", "hysteria_handshake", "proxy_internet", "dns", "exit_identity", "ipv4"}
	if byName["ipv6"] != "unsupported" {
		core = append(core, "ipv6")
	}
	usable := true
	for _, name := range core {
		if byName[name] != "healthy" && byName[name] != "degraded" {
			usable = false
		}
	}
	status := "undetermined"
	if usable {
		status = "healthy"
		for _, check := range checks {
			if check.Status == "degraded" || check.Status == "unhealthy" || check.Status == "undetermined" {
				status = "degraded"
				break
			}
		}
	} else if byName["hysteria_handshake"] == "unhealthy" || byName["proxy_internet"] == "unhealthy" || byName["exit_identity"] == "unhealthy" {
		status = "unhealthy"
	}
	summary := route.ID + " health is undetermined."
	if status == "healthy" {
		summary = route.ID + " is working through the declared proxy exit."
	} else if status == "degraded" {
		summary = route.ID + " carries proxy traffic, but one or more checks are degraded."
	} else if status == "unhealthy" {
		summary = route.ID + " is not carrying usable traffic through the declared proxy exit."
	}
	if latency != nil && (status == "healthy" || status == "degraded") {
		summary = strings.TrimSuffix(summary, ".") + fmt.Sprintf(" (%d ms).", *latency)
	}
	result := HealthResult{SchemaVersion: 1, Route: route.ID, Kind: route.Kind, Status: status, Summary: summary, CheckedAt: checkedAt, LatencyMS: latency, Checks: checks}
	if includePublicIP {
		result.PublicIPv4 = stringPointer(actualIPv4)
		result.PublicIPv6 = stringPointer(actualIPv6)
	}
	return result
}

func addressFamily(address string) string {
	parsed := net.ParseIP(address)
	if parsed != nil && parsed.To4() == nil {
		return "ipv6"
	}
	return "ipv4"
}
