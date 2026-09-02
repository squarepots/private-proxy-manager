package steward

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExplicitProfileRoutingRendersDeterministicServiceSelectors(t *testing.T) {
	state, route := healthFixture(t, "direct", true)
	if _, err := AddProfile(state, map[string]any{
		"profile_id":     "explicit",
		"include_routes": []any{route.ID},
		"routing": map[string]any{
			"china_direct": false,
			"service_routes": []any{
				map[string]any{"service": "youtube", "route": route.ID},
				map[string]any{"service": "openai", "route": route.ID},
			},
		},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddClientTarget(state, map[string]any{"target_id": "desktop", "profile_id": "explicit", "renderer": "mihomo", "mihomo_process_names": []any{"launcher.exe"}}); err != nil {
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
	for _, forbidden := range []string{"\ntun:", "auto-route:", "strict-route:", "auto-detect-interface:", "dns-hijack:", "listen: 0.0.0.0:1053", "nameserver-policy:"} {
		if strings.Contains(yaml, forbidden) {
			t.Fatalf("renderer retained host-wide client/runtime ownership %q:\n%s", forbidden, yaml)
		}
	}
	for _, required := range []string{
		"  - name: RST-Route-route-a\n    type: select\n    proxies:\n",
		"  - GEOSITE,openai,RST-Route-route-a\n",
		"  - GEOSITE,youtube,RST-Route-route-a\n",
		"  - PROCESS-NAME,launcher.exe,Applications\n",
	} {
		if !strings.Contains(yaml, required) {
			t.Fatalf("explicit Profile routing output missed %q:\n%s", required, yaml)
		}
	}
	privateRule := strings.Index(yaml, "  - IP-CIDR6,fe80::/10,DIRECT,no-resolve\n")
	processRule := strings.Index(yaml, "  - PROCESS-NAME,launcher.exe,Applications\n")
	serviceRule := strings.Index(yaml, "  - GEOSITE,openai,RST-Route-route-a\n")
	finalRule := strings.Index(yaml, "  - MATCH,Private Routes\n")
	if privateRule < 0 || processRule < 0 || serviceRule < 0 || finalRule < 0 || !(privateRule < processRule && processRule < serviceRule && serviceRule < finalRule) {
		t.Fatalf("Profile routing rules are not ordered local, process, service, final:\n%s", yaml)
	}
	if strings.Count(yaml, "  - MATCH,") != 1 {
		t.Fatalf("generated YAML must have exactly one final MATCH rule:\n%s", yaml)
	}
	if !strings.Contains(yaml, "  - name: GLOBAL\n") {
		t.Fatal("Mihomo output omitted the explicit global/emergency selector")
	}

	sanitized, _ := json.Marshal(SanitizedContext(state.Inventory))
	if strings.Contains(string(sanitized), "policy") || !strings.Contains(string(sanitized), `"routing"`) || strings.Contains(string(sanitized), "launcher.exe") {
		t.Fatalf("sanitized context did not expose the new routing model safely: %s", sanitized)
	}
}

func TestProfileRoutingExplicitValueOverridesLegacyPolicy(t *testing.T) {
	_, route := healthFixture(t, "direct", false)
	for _, item := range []struct {
		id          string
		policy      string
		chinaDirect bool
		explicit    bool
	}{
		{id: "legacy-balanced", policy: "balanced-cn", chinaDirect: true},
		{id: "legacy-privacy", policy: "privacy", chinaDirect: false},
		{id: "explicit-false", policy: "balanced-cn", chinaDirect: false, explicit: true},
		{id: "explicit-true", policy: "privacy", chinaDirect: true, explicit: true},
	} {
		profile := Profile{ID: item.id, Policy: item.policy, IncludeRoutes: []string{route.ID}}
		if item.explicit {
			profile.Routing = &ProfileRouting{ChinaDirect: item.chinaDirect}
		}
		routing := effectiveProfileRouting(profile)
		if routing.ChinaDirect != item.chinaDirect {
			t.Fatalf("profile %q resolved china_direct=%v, want %v", item.id, routing.ChinaDirect, item.chinaDirect)
		}
	}
}

func TestLegacySchemaOneProfilesLoadWithExplicitRoutingOverride(t *testing.T) {
	var legacy Inventory
	if err := json.Unmarshal([]byte(`{"schema":1,"policies":[{"id":"balanced-cn"}],"profiles":[{"id":"legacy","policy":"balanced-cn"}]}`), &legacy); err != nil {
		t.Fatal(err)
	}
	if err := ValidateInventory(&legacy, t.TempDir(), true); err != nil {
		t.Fatalf("legacy schema-1 policy state no longer loads safely: %v", err)
	}
	if legacy.Profiles[0].Routing != nil || !effectiveProfileRouting(legacy.Profiles[0]).ChinaDirect {
		t.Fatalf("legacy balanced-cn fallback was not preserved: %#v", legacy.Profiles[0])
	}

	var explicit Inventory
	if err := json.Unmarshal([]byte(`{"schema":1,"policies":[{"id":"privacy"}],"profiles":[{"id":"explicit","policy":"privacy","routing":{"china_direct":true}}]}`), &explicit); err != nil {
		t.Fatal(err)
	}
	if err := ValidateInventory(&explicit, t.TempDir(), true); err != nil {
		t.Fatalf("explicit routing state with a legacy policy no longer loads safely: %v", err)
	}
	if explicit.Profiles[0].Routing == nil || !effectiveProfileRouting(explicit.Profiles[0]).ChinaDirect {
		t.Fatalf("explicit routing did not override legacy policy: %#v", explicit.Profiles[0])
	}
}

func TestProfileRoutingChinaToggleAndMultiVariantRouteSelector(t *testing.T) {
	state, route := healthFixture(t, "direct", true)
	if _, err := AddProfile(state, map[string]any{
		"profile_id":     "explicit",
		"include_routes": []any{route.ID},
		"routing": map[string]any{
			"china_direct": true,
			"service_routes": []any{
				map[string]any{"service": "openai", "route": route.ID},
			},
		},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddClientTarget(state, map[string]any{"target_id": "desktop", "profile_id": "explicit", "renderer": "mihomo"}); err != nil {
		t.Fatal(err)
	}
	if _, err := RenderClients(state, "desktop", true); err != nil {
		t.Fatal(err)
	}
	read := func() string {
		data, err := os.ReadFile(filepath.Join(state.PrivateDir, "delivery", "desktop.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		return string(data)
	}
	china := read()
	for _, required := range []string{
		"  - name: RST-Route-route-a\n    type: select\n    proxies:\n      - 'Route-A-HY2-v6'\n      - 'Route-A-HY2-v4'\n",
		"  - GEOSITE,openai,RST-Route-route-a\n",
		"  - DOMAIN-SUFFIX,cn,DIRECT\n",
		"  - GEOSITE,CN,DIRECT\n",
		"  - GEOIP,CN,DIRECT,no-resolve\n",
	} {
		if !strings.Contains(china, required) {
			t.Fatalf("explicit China/multi-variant routing output missed %q:\n%s", required, china)
		}
	}

	profile := findProfile(state.Inventory, "explicit")
	profile.Routing.ChinaDirect = false
	if err := state.Save(false); err != nil {
		t.Fatal(err)
	}
	if _, err := RenderClients(state, "desktop", true); err != nil {
		t.Fatal(err)
	}
	withoutChina := read()
	for _, forbidden := range []string{"DOMAIN-SUFFIX,cn,DIRECT", "GEOSITE,CN,DIRECT", "GEOIP,CN,DIRECT,no-resolve"} {
		if strings.Contains(withoutChina, forbidden) {
			t.Fatalf("china_direct=false retained China-direct rule %q:\n%s", forbidden, withoutChina)
		}
	}
	if !strings.Contains(withoutChina, "GEOSITE,openai,RST-Route-route-a") {
		t.Fatal("service routing disappeared when China-direct routing was disabled")
	}
}

func TestProfileRoutingReferencesFailClosed(t *testing.T) {
	state, route := healthFixture(t, "direct", false)
	base := func(include []any, target string) map[string]any {
		return map[string]any{
			"profile_id":     "candidate",
			"include_routes": include,
			"routing":        map[string]any{"service_routes": []any{map[string]any{"service": "openai", "route": target}}},
		}
	}
	for _, test := range []struct {
		name    string
		context map[string]any
	}{
		{name: "unknown", context: base([]any{"*"}, "missing-route")},
		{name: "excluded", context: base([]any{}, route.ID)},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, err := AddProfile(state, test.context); err == nil {
				t.Fatal("invalid service Route reference was accepted")
			}
			preflight, err := NewPreflight("add-profile", "", state, test.context, false)
			if err != nil || preflight.Ready || !contains(preflight.Conflicts, "profile-routing-invalid") {
				t.Fatalf("invalid service Route reference passed preflight: %#v err=%v", preflight, err)
			}
		})
	}
	findRoute(state.Inventory, route.ID).Enabled = false
	disabled := base([]any{"*"}, route.ID)
	if _, err := AddProfile(state, disabled); err == nil || !strings.Contains(err.Error(), "disabled Route") {
		t.Fatalf("disabled service Route was not rejected: %v", err)
	}
}
