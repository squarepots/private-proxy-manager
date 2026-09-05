package steward

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"unicode"
)

type ProfileRouting struct {
	Rules []ProfileRoutingRule `json:"rules,omitempty"`
	// Compatibility projections are not schema-2 state. They keep released
	// internal migration/test paths readable while canonical state uses Rules.
	ChinaDirect   bool                  `json:"-"`
	ServiceRoutes []ProfileServiceRoute `json:"-"`
}

type ProfileServiceRoute struct {
	Service string
	Route   string
}

type ProfileRoutingRule struct {
	Match  ProfileRoutingMatch  `json:"match"`
	Action ProfileRoutingAction `json:"action"`
}

type ProfileRoutingMatch struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type ProfileRoutingAction struct {
	Type  string `json:"type"`
	Route string `json:"route,omitempty"`
}

func (routing *ProfileRouting) UnmarshalJSON(data []byte) error {
	type disk struct {
		Rules []ProfileRoutingRule `json:"rules,omitempty"`
	}
	var decoded disk
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	routing.Rules = decoded.Rules
	routing.refreshCompatibilityProjection()
	return nil
}

func (routing ProfileRouting) MarshalJSON() ([]byte, error) {
	normalized, err := normalizeProfileRouting(&routing)
	if err != nil {
		return nil, err
	}
	type disk struct {
		Rules []ProfileRoutingRule `json:"rules,omitempty"`
	}
	return json.Marshal(disk{Rules: normalized.Rules})
}

func (routing *ProfileRouting) refreshCompatibilityProjection() {
	routing.ChinaDirect = false
	routing.ServiceRoutes = []ProfileServiceRoute{}
	for _, rule := range routing.Rules {
		if rule.Action.Type == "route" {
			routing.ServiceRoutes = append(routing.ServiceRoutes, ProfileServiceRoute{
				Service: rule.Match.Value,
				Route:   rule.Action.Route,
			})
		}
	}
}

func defaultProfileRouting() *ProfileRouting {
	return &ProfileRouting{Rules: []ProfileRoutingRule{}}
}

func cloneProfileRouting(routing *ProfileRouting) *ProfileRouting {
	if routing == nil {
		return nil
	}
	out := &ProfileRouting{
		Rules:         make([]ProfileRoutingRule, len(routing.Rules)),
		ChinaDirect:   routing.ChinaDirect,
		ServiceRoutes: append([]ProfileServiceRoute(nil), routing.ServiceRoutes...),
	}
	copy(out.Rules, routing.Rules)
	return out
}

func normalizeProfileRouting(routing *ProfileRouting) (*ProfileRouting, error) {
	if routing == nil {
		return nil, errors.New("routing must be an object")
	}
	out := cloneProfileRouting(routing)
	if len(out.Rules) == 0 && len(out.ServiceRoutes) > 0 {
		for _, binding := range out.ServiceRoutes {
			out.Rules = append(out.Rules, ProfileRoutingRule{
				Match:  ProfileRoutingMatch{Type: "geosite", Value: binding.Service},
				Action: ProfileRoutingAction{Type: "route", Route: binding.Route},
			})
		}
	} else if len(out.Rules) > 0 && len(out.ServiceRoutes) > 0 {
		index := 0
		for i := range out.Rules {
			if out.Rules[i].Action.Type != "route" {
				continue
			}
			if index < len(out.ServiceRoutes) {
				out.Rules[i].Action.Route = out.ServiceRoutes[index].Route
			}
			index++
		}
	}
	if len(out.Rules) == 0 && out.ChinaDirect {
		out.Rules = append(out.Rules, legacyChinaDirectRules()...)
	}
	seen := map[string]bool{}
	for i := range out.Rules {
		rule := &out.Rules[i]
		rule.Match.Type = strings.ToLower(strings.TrimSpace(rule.Match.Type))
		rule.Match.Value = strings.TrimSpace(rule.Match.Value)
		rule.Action.Type = strings.ToLower(strings.TrimSpace(rule.Action.Type))
		rule.Action.Route = strings.TrimSpace(rule.Action.Route)
		switch rule.Match.Type {
		case "domain_suffix", "geosite", "geoip":
		default:
			return nil, fmt.Errorf("unsupported routing match type %q", rule.Match.Type)
		}
		if !validRoutingValue(rule.Match.Value) {
			return nil, errors.New("routing match value must be non-empty and contain no comma, line break, or control character")
		}
		switch rule.Action.Type {
		case "direct":
			if rule.Action.Route != "" {
				return nil, errors.New("direct routing action cannot include a Route ID")
			}
		case "route":
			if rule.Action.Route == "" {
				return nil, errors.New("route routing action requires a Route ID")
			}
		default:
			return nil, fmt.Errorf("unsupported routing action type %q", rule.Action.Type)
		}
		key := rule.Match.Type + "\x00" + strings.ToLower(rule.Match.Value)
		if seen[key] {
			return nil, fmt.Errorf("routing matcher %q is duplicated", rule.Match.Value)
		}
		seen[key] = true
	}
	out.refreshCompatibilityProjection()
	return out, nil
}

func validRoutingValue(value string) bool {
	if value == "" || strings.ContainsAny(value, ",\r\n") {
		return false
	}
	for _, r := range value {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func profileRoutingFromContext(context map[string]any) (*ProfileRouting, bool, error) {
	if hasField(context, "routing") {
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
	if hasField(context, "policy") {
		switch strings.ToLower(stringField(context, "policy")) {
		case "privacy", "":
			return defaultProfileRouting(), true, nil
		case "balanced-cn":
			normalized, err := normalizeProfileRouting(&ProfileRouting{Rules: legacyChinaDirectRules()})
			return normalized, true, err
		default:
			return nil, true, errors.New("legacy policy is unsupported; use routing.rules")
		}
	}
	return nil, false, nil
}

func effectiveProfileRouting(profile Profile) ProfileRouting {
	if profile.Routing == nil {
		if strings.EqualFold(profile.Policy, "balanced-cn") {
			return ProfileRouting{Rules: legacyChinaDirectRules()}
		}
		return ProfileRouting{Rules: []ProfileRoutingRule{}}
	}
	routing, err := normalizeProfileRouting(profile.Routing)
	if err == nil {
		return *routing
	}
	return ProfileRouting{Rules: append([]ProfileRoutingRule(nil), profile.Routing.Rules...)}
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
	for _, rule := range routing.Rules {
		if rule.Action.Type != "route" {
			continue
		}
		route := findRoute(inv, rule.Action.Route)
		if route == nil {
			return fmt.Errorf("routing rule references unknown Route %q", rule.Action.Route)
		}
		if !route.Enabled {
			return fmt.Errorf("routing rule references disabled Route %q", rule.Action.Route)
		}
		if !profileRouteIncluded(profile, rule.Action.Route) {
			return fmt.Errorf("routing rule references Route %q outside Profile", rule.Action.Route)
		}
	}
	return nil
}
