package steward

import (
	"net"
	"os"
	"path/filepath"
)

func NewPreflight(operation, target string, state *State, context map[string]any, approved bool) (Preflight, error) {
	capability, err := CapabilityByID(operation)
	if err != nil {
		return Preflight{}, err
	}
	missing, conflicts, decisions, effects := []string{}, []string{}, []string{}, []string{}
	inv := state.Inventory
	if inv.Schema != InventorySchema {
		conflicts = append(conflicts, "state-schema-unsupported")
	}
	if err := ValidateInventory(inv, state.PrivateDir, false); err != nil {
		conflicts = append(conflicts, "inventory-invalid")
	}
	server := func(id string) *Server {
		for i := range inv.Servers {
			if inv.Servers[i].ID == id {
				return &inv.Servers[i]
			}
		}
		return nil
	}
	link := func(id string) *Link {
		for i := range inv.Links {
			if inv.Links[i].ID == id {
				return &inv.Links[i]
			}
		}
		return nil
	}
	route := func(id string) *Route {
		for i := range inv.Routes {
			if inv.Routes[i].ID == id || inv.Routes[i].DisplayName == id {
				return &inv.Routes[i]
			}
		}
		return nil
	}
	provider := func(id string) *Provider {
		for i := range inv.Providers {
			if inv.Providers[i].ID == id {
				return &inv.Providers[i]
			}
		}
		return nil
	}
	profile := func(id string) *Profile {
		for i := range inv.Profiles {
			if inv.Profiles[i].ID == id {
				return &inv.Profiles[i]
			}
		}
		return nil
	}
	clientTarget := func(id string) *ClientTarget {
		for i := range inv.ClientTargets {
			if inv.ClientTargets[i].ID == id {
				return &inv.ClientTargets[i]
			}
		}
		return nil
	}
	require := func(fields ...string) {
		for _, field := range fields {
			if stringField(context, field) == "" {
				missing = append(missing, replaceUnderscore(field))
			}
		}
	}

	switch operation {
	case "status":
		effects = append(effects, "read-sanitized-local-state")
	case "drift":
		effects = append(effects, "read-sanitized-local-and-observed-state")
	case "audit":
		if target == "" {
			missing = append(missing, "target-route")
		} else if route(target) == nil {
			conflicts = append(conflicts, "target-route-missing")
		}
		effects = append(effects, "read-remote-supported-state")
	case "health":
		r := route(target)
		if target == "" {
			missing = append(missing, "target-route")
		} else if r == nil {
			conflicts = append(conflicts, "target-route-missing")
		} else {
			if r.State != "deployed" || !r.Enabled {
				conflicts = append(conflicts, "target-route-not-deployed")
			}
			if _, err := ResolveSecret(r.PayloadSecretRef, state.PrivateDir, nil); err != nil {
				conflicts = append(conflicts, "required-client-payload-missing")
			}
		}
		if raw, ok := context["include_public_ip"]; ok {
			if _, valid := raw.(bool); !valid {
				conflicts = append(conflicts, "include-public-ip-must-be-boolean")
			}
		}
		effects = append(effects, "read-remote-supported-state", "download-verified-local-health-helper-if-absent", "contact-public-health-endpoints-through-route", "write-sanitized-observed-health")
	case "bootstrap":
		effects = append(effects, "create-local-private-state")
	case "add-server":
		require("server_id", "public_ipv4", "ssh_user", "ssh_key_path", "host_ownership")
		if id := stringField(context, "server_id"); id != "" && server(id) != nil {
			conflicts = append(conflicts, "server-id-already-exists")
		}
		if u := stringField(context, "ssh_user"); u != "" && !unixUserPattern.MatchString(u) {
			conflicts = append(conflicts, "ssh-user-invalid")
		}
		if own := stringField(context, "host_ownership"); own != "" && own != "dedicated" {
			conflicts = append(conflicts, "host-ownership-unsupported")
		}
		if ip := stringField(context, "public_ipv4"); ip != "" && (net.ParseIP(ip) == nil || net.ParseIP(ip).To4() == nil) {
			conflicts = append(conflicts, "public-ipv4-invalid")
		}
		effects = append(effects, "update-local-desired-state")
	case "add-link":
		require("link_id", "entry_server", "exit_server")
		entry, exit := stringField(context, "entry_server"), stringField(context, "exit_server")
		if entry != "" && server(entry) == nil {
			conflicts = append(conflicts, "entry-server-missing")
		}
		if exit != "" && server(exit) == nil {
			conflicts = append(conflicts, "exit-server-missing")
		}
		if entry != "" && entry == exit {
			conflicts = append(conflicts, "link-endpoints-must-differ")
		}
		if id := stringField(context, "link_id"); id != "" && link(id) != nil {
			conflicts = append(conflicts, "link-id-already-exists")
		}
		effects = append(effects, "allocate-local-link-and-keys")
	case "add-route":
		require("route_id", "kind", "entry_server")
		kind := stringField(context, "kind")
		if kind != "" && kind != "direct" && kind != "relay" {
			conflicts = append(conflicts, "unsupported-route-kind")
		}
		if entry := stringField(context, "entry_server"); entry != "" && server(entry) == nil {
			conflicts = append(conflicts, "entry-server-missing")
		}
		if kind == "relay" {
			if stringField(context, "exit_server") == "" {
				missing = append(missing, "exit-server")
			}
			if stringField(context, "link_id") == "" {
				missing = append(missing, "link-id")
			}
		}
		if id := stringField(context, "route_id"); id != "" && route(id) != nil {
			conflicts = append(conflicts, "route-id-already-exists")
		}
		effects = append(effects, "generate-local-route-credentials-and-update-desired-state")
	case "add-provider":
		require("provider_id", "url")
		if id := stringField(context, "provider_id"); id != "" && provider(id) != nil {
			conflicts = append(conflicts, "provider-id-already-exists")
		}
		if value := stringField(context, "url"); value != "" && !ValidateProviderURL(value) {
			conflicts = append(conflicts, "provider-url-invalid")
		}
		effects = append(effects, "write-provider-url-to-local-secret-storage", "update-local-desired-state")
	case "update-provider":
		if target == "" {
			missing = append(missing, "target-provider")
		} else if provider(target) == nil {
			conflicts = append(conflicts, "target-provider-missing")
		}
		if !anyField(context, "url", "display_name", "interval_seconds", "enabled") {
			missing = append(missing, "provider-change")
		}
		effects = append(effects, "update-local-provider-state")
	case "remove-provider":
		if target == "" {
			missing = append(missing, "target-provider")
		} else if provider(target) == nil {
			conflicts = append(conflicts, "target-provider-missing")
		}
		for _, p := range inv.Profiles {
			if contains(p.IncludeProviders, target) {
				conflicts = append(conflicts, "provider-still-referenced-by-profile")
			}
		}
		effects = append(effects, "remove-local-provider-state-and-url-secret")
	case "add-profile":
		require("profile_id")
		if id := stringField(context, "profile_id"); id != "" && profile(id) != nil {
			conflicts = append(conflicts, "profile-id-already-exists")
		}
		effects = append(effects, "update-local-profile-selection")
	case "update-profile":
		if target == "" {
			missing = append(missing, "target-profile")
		} else if profile(target) == nil {
			conflicts = append(conflicts, "target-profile-missing")
		}
		if !anyField(context, "policy", "include_routes", "include_providers") {
			missing = append(missing, "profile-change")
		}
		effects = append(effects, "update-local-profile-selection")
	case "remove-profile":
		if target == "" {
			missing = append(missing, "target-profile")
		} else if profile(target) == nil {
			conflicts = append(conflicts, "target-profile-missing")
		}
		for _, t := range inv.ClientTargets {
			if t.Profile == target {
				conflicts = append(conflicts, "profile-still-referenced-by-client-target")
			}
		}
		effects = append(effects, "remove-local-profile")
	case "add-client-target":
		require("target_id", "profile_id", "renderer")
		if id := stringField(context, "target_id"); id != "" && clientTarget(id) != nil {
			conflicts = append(conflicts, "client-target-id-already-exists")
		}
		if id := stringField(context, "profile_id"); id != "" && profile(id) == nil {
			conflicts = append(conflicts, "client-target-profile-missing")
		}
		renderer := stringField(context, "renderer")
		if renderer != "" && renderer != "mihomo" && renderer != "shadowrocket" {
			conflicts = append(conflicts, "client-target-renderer-unsupported")
		}
		effects = append(effects, "add-local-client-target")
	case "update-client-target":
		if target == "" {
			missing = append(missing, "target-client-target")
		} else if clientTarget(target) == nil {
			conflicts = append(conflicts, "target-client-target-missing")
		}
		if !anyField(context, "profile_id", "delivery") {
			missing = append(missing, "client-target-change")
		}
		if id := stringField(context, "profile_id"); id != "" && profile(id) == nil {
			conflicts = append(conflicts, "client-target-profile-missing")
		}
		effects = append(effects, "update-local-client-target")
	case "remove-client-target":
		if target == "" {
			missing = append(missing, "target-client-target")
		} else if t := clientTarget(target); t == nil {
			conflicts = append(conflicts, "target-client-target-missing")
		} else if t.SubscriptionSecretRef != "" {
			conflicts = append(conflicts, "client-target-has-subscription-state")
		}
		effects = append(effects, "remove-local-client-target")
	case "deploy-route":
		r := route(target)
		if r == nil {
			missing = append(missing, "target-route")
		} else {
			for _, ref := range []string{r.PayloadSecretRef, r.CredentialSecretRef} {
				if _, err := ResolveSecret(ref, state.PrivateDir, nil); err != nil {
					conflicts = append(conflicts, "required-secret-missing")
				}
			}
			seen := map[string]bool{}
			for _, id := range []string{r.EntryServer, r.ExitServer} {
				if seen[id] {
					continue
				}
				seen[id] = true
				s := server(id)
				if s == nil {
					conflicts = append(conflicts, "server-missing")
					continue
				}
				if s.Compute.HostOwnership != "dedicated" {
					conflicts = append(conflicts, "dedicated-host-not-confirmed")
				}
				if !unixUserPattern.MatchString(s.SSH.User) {
					conflicts = append(conflicts, "ssh-user-invalid")
				}
				if info, err := os.Stat(s.SSH.KeyPath); err != nil || !info.Mode().IsRegular() {
					conflicts = append(conflicts, "ssh-key-missing")
				}
			}
			effects = append(effects, "deploy-route:"+r.ID)
		}
	case "render-client":
		if target != "" && clientTarget(target) == nil {
			conflicts = append(conflicts, "target-client-target-missing")
		}
		if countEnabledRoutes(inv) == 0 {
			missing = append(missing, "enabled-route")
		}
		effects = append(effects, "write-private-client-artifacts")
	case "publish-subscription":
		if target == "" {
			missing = append(missing, "target-client-target")
		} else if t := clientTarget(target); t == nil || t.Renderer != "shadowrocket" {
			conflicts = append(conflicts, "target-client-target-not-shadowrocket")
		} else if t.SubscriptionSecretRef == "" {
			if stringField(context, "worker_name") == "" {
				missing = append(missing, "worker-name")
			}
			if stringField(context, "host") == "" {
				missing = append(missing, "host")
			}
		} else if _, err := ResolveSecret(t.SubscriptionSecretRef, state.PrivateDir, nil); err != nil {
			conflicts = append(conflicts, "subscription-state-missing")
		}
		if countEnabledRoutes(inv) == 0 {
			missing = append(missing, "enabled-route")
		}
		effects = append(effects, "publish-private-subscription-payload")
	case "rotate-subscription-token":
		if target == "" {
			missing = append(missing, "target-client-target")
		} else if t := clientTarget(target); t == nil {
			conflicts = append(conflicts, "target-client-target-missing")
		} else if t.Renderer != "shadowrocket" {
			conflicts = append(conflicts, "target-client-target-not-shadowrocket")
		} else if t.SubscriptionSecretRef == "" {
			conflicts = append(conflicts, "client-target-has-no-subscription-state")
		}
		decisions = append(decisions, "explicit-current-authorization-for-target-scoped-token-rotation")
		effects = append(effects, "rotate-only-one-client-target-subscription-token", "require-subscription-republication", "leave-route-and-other-client-credentials-unchanged")
	case "migrate-route":
		if route(target) == nil {
			missing = append(missing, "target-route")
		}
		if replacement := stringField(context, "replacement_server_id"); replacement == "" {
			missing = append(missing, "replacement-server")
		} else if server(replacement) == nil {
			conflicts = append(conflicts, "replacement-server-not-in-inventory")
		}
		effects = append(effects, "create-and-validate-overlap-before-any-retirement")
	case "backup":
		effects = append(effects, "write-encrypted-local-recovery-archive")
	case "recover":
		effects = append(effects, "restore-local-canonical-state")
	}
	missing, conflicts, decisions, effects = sortedUnique(missing), sortedUnique(conflicts), sortedUnique(decisions), sortedUnique(effects)
	complete := len(missing) == 0 && len(conflicts) == 0
	authorized := capability.AuthorizationClass != "credential-change" || approved
	var targetValue *string
	if target != "" {
		targetValue = stringPointer(target)
	}
	return Preflight{SchemaVersion: 1, Operation: operation, Target: targetValue, State: capability.State, Executor: capability.Executor, Mutation: capability.Mutation, AuthorizationClass: capability.AuthorizationClass, ContextComplete: complete, Authorized: authorized, Ready: complete && authorized, MissingContext: missing, Conflicts: conflicts, UserDecisions: decisions, ExpectedEffects: effects, Rule: authorityRule, RequiresLocalSecretPrompt: capability.RequiresLocalSecretPrompt}, nil
}

func NewRecoveryPreflight(privateDir string, context map[string]any) Preflight {
	missing, conflicts := []string{}, []string{}
	archive := stringField(context, "archive_path")
	if archive == "" {
		missing = append(missing, "recovery-archive-path")
	} else if full, err := filepath.Abs(archive); err != nil {
		conflicts = append(conflicts, "recovery-archive-path-invalid")
	} else if info, err := os.Stat(full); err != nil || !info.Mode().IsRegular() {
		conflicts = append(conflicts, "recovery-archive-missing")
	}
	if _, err := os.Stat(privateDir); err == nil {
		conflicts = append(conflicts, "private-state-target-already-exists")
	}
	ready := len(missing) == 0 && len(conflicts) == 0
	return Preflight{SchemaVersion: 1, Operation: "recover", Target: nil, State: "supported", Executor: "local-assisted", Mutation: true, AuthorizationClass: "local-write", ContextComplete: ready, Authorized: true, Ready: ready, MissingContext: missing, Conflicts: conflicts, UserDecisions: []string{"enter-recovery-password-only-in-local-7zip-prompt"}, ExpectedEffects: []string{"no-remote-infrastructure-change", "reset-observed-state", "restore-local-canonical-private-state", "rewrite-restored-ssh-key-paths"}, Rule: authorityRule, RequiresLocalSecretPrompt: true}
}

func replaceUnderscore(value string) string {
	out := []byte(value)
	for i := range out {
		if out[i] == '_' {
			out[i] = '-'
		}
	}
	return string(out)
}
func anyField(context map[string]any, names ...string) bool {
	for _, name := range names {
		if hasField(context, name) {
			return true
		}
	}
	return false
}
func contains(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}
func countEnabledRoutes(inv *Inventory) int {
	n := 0
	for _, r := range inv.Routes {
		if r.Enabled {
			n++
		}
	}
	return n
}
