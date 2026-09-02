package steward

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
)

// ProfileRouting is the schema-1 routing contract owned by Route Steward.
// A nil value on a loaded Profile is intentional: it means the Profile came
// from the legacy policy-only shape and should use the compatibility fallback.
type ProfileRouting struct {
	ChinaDirect   bool                  `json:"china_direct"`
	ServiceRoutes []ProfileServiceRoute `json:"service_routes,omitempty"`
}

type ProfileServiceRoute struct {
	Service string `json:"service"`
	Route   string `json:"route"`
}

var supportedProfileServices = map[string]bool{
	"openai":  true,
	"youtube": true,
}

func defaultProfileRouting() *ProfileRouting {
	return &ProfileRouting{ChinaDirect: false, ServiceRoutes: []ProfileServiceRoute{}}
}

func cloneProfileRouting(routing *ProfileRouting) *ProfileRouting {
	if routing == nil {
		return nil
	}
	out := &ProfileRouting{ChinaDirect: routing.ChinaDirect, ServiceRoutes: append([]ProfileServiceRoute(nil), routing.ServiceRoutes...)}
	return out
}

func normalizeProfileRouting(routing *ProfileRouting) (*ProfileRouting, error) {
	if routing == nil {
		return nil, errors.New("routing must be an object")
	}
	out := cloneProfileRouting(routing)
	seen := map[string]bool{}
	for i := range out.ServiceRoutes {
		service := strings.ToLower(strings.TrimSpace(out.ServiceRoutes[i].Service))
		route := strings.TrimSpace(out.ServiceRoutes[i].Route)
		if !supportedProfileServices[service] {
			return nil, fmt.Errorf("unsupported service %q; supported services are openai and youtube", out.ServiceRoutes[i].Service)
		}
		if route == "" {
			return nil, fmt.Errorf("service route %q has no Route ID", service)
		}
		if seen[service] {
			return nil, fmt.Errorf("service %q has more than one Route binding", service)
		}
		seen[service] = true
		out.ServiceRoutes[i].Service = service
		out.ServiceRoutes[i].Route = route
	}
	sort.Slice(out.ServiceRoutes, func(i, j int) bool {
		if out.ServiceRoutes[i].Service == out.ServiceRoutes[j].Service {
			return out.ServiceRoutes[i].Route < out.ServiceRoutes[j].Route
		}
		return out.ServiceRoutes[i].Service < out.ServiceRoutes[j].Service
	})
	return out, nil
}

func profileRoutingFromContext(context map[string]any) (*ProfileRouting, bool, error) {
	if !hasField(context, "routing") {
		return nil, false, nil
	}
	raw := context["routing"]
	if raw == nil {
		return nil, true, errors.New("routing must be an object")
	}
	b, err := json.Marshal(raw)
	if err != nil {
		return nil, true, fmt.Errorf("decode routing: %w", err)
	}
	var routing ProfileRouting
	if err := json.Unmarshal(b, &routing); err != nil {
		return nil, true, fmt.Errorf("decode routing: %w", err)
	}
	normalized, err := normalizeProfileRouting(&routing)
	if err != nil {
		return nil, true, err
	}
	return normalized, true, nil
}

func legacyPolicyID(policy string) bool {
	switch strings.ToLower(strings.TrimSpace(policy)) {
	case "privacy", "balanced-cn":
		return true
	default:
		return false
	}
}

func effectiveProfileRouting(profile Profile) ProfileRouting {
	if profile.Routing != nil {
		routing, err := normalizeProfileRouting(profile.Routing)
		if err == nil {
			return *routing
		}
		return ProfileRouting{ChinaDirect: profile.Routing.ChinaDirect, ServiceRoutes: append([]ProfileServiceRoute(nil), profile.Routing.ServiceRoutes...)}
	}
	return ProfileRouting{ChinaDirect: strings.EqualFold(strings.TrimSpace(profile.Policy), "balanced-cn"), ServiceRoutes: []ProfileServiceRoute{}}
}

func profileRouteIncluded(profile Profile, routeID string) bool {
	return contains(profile.IncludeRoutes, "*") || contains(profile.IncludeRoutes, routeID)
}

func validateProfileRouting(inv *Inventory, profile Profile) error {
	if profile.Routing == nil {
		return nil
	}
	routing, err := normalizeProfileRouting(profile.Routing)
	if err != nil {
		return err
	}
	for _, binding := range routing.ServiceRoutes {
		var route *Route
		for i := range inv.Routes {
			if inv.Routes[i].ID == binding.Route {
				route = &inv.Routes[i]
				break
			}
		}
		if route == nil {
			return fmt.Errorf("service %q references unknown Route %q", binding.Service, binding.Route)
		}
		if !route.Enabled {
			return fmt.Errorf("service %q references disabled Route %q", binding.Service, binding.Route)
		}
		if !profileRouteIncluded(profile, binding.Route) {
			return fmt.Errorf("service %q references Route %q outside Profile", binding.Service, binding.Route)
		}
	}
	return nil
}
