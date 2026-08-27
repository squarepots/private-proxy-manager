package steward

import (
	"errors"
	"regexp"
	"sort"
	"strings"
)

const maxMihomoProcessNames = 32

var mihomoProcessNamePattern = regexp.MustCompile(`^(?:[A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]{0,62}[A-Za-z0-9])$`)

func validateMihomoProcessNames(values []string) ([]string, error) {
	if len(values) > maxMihomoProcessNames {
		return nil, errors.New("mihomo process names exceed the supported limit")
	}
	out := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, value := range values {
		name := strings.TrimSpace(value)
		key := strings.ToLower(name)
		if name == "" || !mihomoProcessNamePattern.MatchString(name) || strings.Contains(name, "..") {
			return nil, errors.New("mihomo process names must be plain executable or package names")
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, name)
	}
	sort.SliceStable(out, func(i, j int) bool {
		left, right := strings.ToLower(out[i]), strings.ToLower(out[j])
		if left == right {
			return out[i] < out[j]
		}
		return left < right
	})
	return out, nil
}

func mihomoProcessNamesFromContext(context map[string]any) ([]string, error) {
	if context == nil {
		return nil, nil
	}
	raw, ok := context["mihomo_process_names"]
	if !ok || raw == nil {
		return nil, nil
	}
	values, ok := raw.([]any)
	if !ok {
		if strings, ok := raw.([]string); ok {
			return validateMihomoProcessNames(strings)
		}
		return nil, errors.New("mihomo_process_names must be an array of strings")
	}
	out := make([]string, 0, len(values))
	for _, item := range values {
		value, ok := item.(string)
		if !ok {
			return nil, errors.New("mihomo_process_names must be an array of strings")
		}
		out = append(out, value)
	}
	return validateMihomoProcessNames(out)
}
