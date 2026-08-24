package steward

import (
	"fmt"
	"strconv"
	"strings"
)

// Keep the supported range deliberately small. It is large enough to avoid
// per-port UDP throttling while keeping the exposed firewall surface and
// on-demand diagnostics bounded.
const maxPortHoppingPorts = 8

type PortHopping struct {
	StartPort int `json:"start_port"`
	EndPort   int `json:"end_port"`
}

func parsePortHoppingRange(value string) (*PortHopping, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	parts := strings.Split(value, "-")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return nil, fmt.Errorf("port_hopping must be one consecutive UDP port range such as 20000-20007")
	}
	start, startErr := strconv.Atoi(parts[0])
	end, endErr := strconv.Atoi(parts[1])
	if startErr != nil || endErr != nil || start < 1 || end > 65535 || end <= start {
		return nil, fmt.Errorf("port_hopping must be a valid ascending UDP port range")
	}
	if end-start+1 > maxPortHoppingPorts {
		return nil, fmt.Errorf("port_hopping supports at most %d consecutive UDP ports", maxPortHoppingPorts)
	}
	return &PortHopping{StartPort: start, EndPort: end}, nil
}

func validatePortHopping(port int, hopping *PortHopping) error {
	if hopping == nil {
		return nil
	}
	if hopping.StartPort < 1 || hopping.EndPort > 65535 || hopping.EndPort <= hopping.StartPort {
		return errorsInvalidPortHopping()
	}
	if hopping.EndPort-hopping.StartPort+1 > maxPortHoppingPorts || hopping.StartPort != port {
		return errorsInvalidPortHopping()
	}
	return nil
}

func errorsInvalidPortHopping() error {
	return fmt.Errorf("port_hopping must start at listen_port and contain 2..%d consecutive UDP ports", maxPortHoppingPorts)
}

func portHoppingText(hopping *PortHopping) string {
	if hopping == nil {
		return ""
	}
	return fmt.Sprintf("%d-%d", hopping.StartPort, hopping.EndPort)
}

func samePortHopping(first, second *PortHopping) bool {
	if first == nil || second == nil {
		return first == nil && second == nil
	}
	return first.StartPort == second.StartPort && first.EndPort == second.EndPort
}

func clonePortHopping(hopping *PortHopping) *PortHopping {
	if hopping == nil {
		return nil
	}
	return &PortHopping{StartPort: hopping.StartPort, EndPort: hopping.EndPort}
}

func routePortRange(route Route) (int, int, error) {
	if err := validatePortHopping(route.ListenPort, route.PortHopping); err != nil {
		return 0, 0, err
	}
	if route.PortHopping == nil {
		return route.ListenPort, route.ListenPort, nil
	}
	return route.PortHopping.StartPort, route.PortHopping.EndPort, nil
}

func portRangesOverlap(firstStart, firstEnd, secondStart, secondEnd int) bool {
	return firstStart <= secondEnd && secondStart <= firstEnd
}
