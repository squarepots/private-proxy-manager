package steward

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"time"
)

func normalizeProxyListen(value string) (string, error) {
	host, portText, err := net.SplitHostPort(value)
	if err != nil {
		return "", errors.New("proxy listener must be an IP address and port")
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return "", errors.New("proxy listener must use a loopback IP address")
	}
	port, err := strconv.Atoi(portText)
	if err != nil || port < 1 || port > 65535 {
		return "", errors.New("proxy listener port is invalid")
	}
	return net.JoinHostPort(ip.String(), strconv.Itoa(port)), nil
}

func prepareClientProxy(ctx context.Context, state *State, targetID string) (ClientTarget, Route, string, string, bool, error) {
	target := findClientTarget(state.Inventory, targetID)
	if target == nil || target.Renderer != "hysteria2" {
		return ClientTarget{}, Route{}, "", "", false, fmt.Errorf("ClientTarget %q is not a Hysteria2 target", targetID)
	}
	profile := findProfile(state.Inventory, target.Profile)
	if profile == nil {
		return ClientTarget{}, Route{}, "", "", false, fmt.Errorf("ClientTarget %q references an unknown Profile", targetID)
	}
	route, _, err := headlessRouteNode(state, *profile, *target)
	if err != nil {
		return ClientTarget{}, Route{}, "", "", false, err
	}
	rendered, err := RenderClients(state, target.ID, true)
	if err != nil {
		return ClientTarget{}, Route{}, "", "", false, err
	}
	binary, downloaded, err := ensureHysteriaClient(ctx, state)
	if err != nil {
		return ClientTarget{}, Route{}, "", "", false, err
	}
	if len(rendered.Outputs) != 1 || filepath.Base(rendered.Outputs[0].Path) != target.ID+".json" {
		return ClientTarget{}, Route{}, "", "", false, errors.New("Hysteria2 ClientTarget render did not produce one private JSON artifact")
	}
	configPath := rendered.Outputs[0].Path
	return *target, route, configPath, binary, downloaded, nil
}

func CheckClientProxy(ctx context.Context, state *State, targetID string) (ClientProxyCheckResult, error) {
	target, route, configPath, binary, downloaded, err := prepareClientProxy(ctx, state, targetID)
	result := ClientProxyCheckResult{SchemaVersion: 1, ClientTarget: targetID, Status: "undetermined", Detail: "client-not-started", ClientVersion: hysteriaClientVersion, Downloaded: downloaded}
	if err != nil {
		return result, err
	}
	listen, err := normalizeProxyListen(target.Listen)
	if err != nil {
		return result, err
	}
	result.Route = route.ID
	result.HTTPProxy = "http://" + listen
	result.SOCKS5Proxy = "socks5://" + listen
	session, err := startClientProxyCheck(ctx, binary, configPath, listen)
	if err != nil {
		result.Detail = "client-start-failed"
		return result, err
	}
	defer session.Stop()
	requestContext, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	client, err := healthHTTPClient(result.HTTPProxy)
	if err != nil {
		return result, err
	}
	trace, _, err := fetchHealthTrace(requestContext, client, defaultHealthEndpoints.IPv4)
	if err != nil {
		result.Status = "unhealthy"
		result.Detail = "proxy-request-failed"
		return result, nil
	}
	exit := findServer(state.Inventory, route.ExitServer)
	if exit == nil || trace["ip"] != exit.Network.ExpectedEgressIPv4 {
		result.Status = "unhealthy"
		result.Detail = "exit-identity-mismatch"
		return result, nil
	}
	result.Status = "healthy"
	result.Detail = "real-http-request-through-managed-route"
	return result, nil
}

func RunClientProxy(ctx context.Context, state *State, targetID string) error {
	_, _, configPath, binary, _, err := prepareClientProxy(ctx, state, targetID)
	if err != nil {
		return err
	}
	command := exec.CommandContext(ctx, binary, "client", "--config", configPath, "--disable-update-check", "--log-level", "warn", "--log-format", "json")
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("Hysteria2 client stopped: %w", err)
	}
	return nil
}

type clientProxySession struct {
	cancel context.CancelFunc
	cmd    *exec.Cmd
	done   chan error
	once   sync.Once
}

func (session *clientProxySession) Stop() {
	session.once.Do(func() {
		session.cancel()
		if session.cmd.Process != nil {
			_ = session.cmd.Process.Kill()
		}
		select {
		case <-session.done:
		case <-time.After(2 * time.Second):
		}
	})
}

func startClientProxyCheck(ctx context.Context, binary, configPath, listen string) (*clientProxySession, error) {
	if err := ensureProxyListenerAvailable(listen); err != nil {
		return nil, err
	}
	processContext, cancel := context.WithCancel(ctx)
	command := exec.CommandContext(processContext, binary, "client", "--config", configPath, "--disable-update-check", "--log-level", "warn", "--log-format", "json")
	command.Stdout, command.Stderr = io.Discard, io.Discard
	if err := command.Start(); err != nil {
		cancel()
		return nil, err
	}
	session := &clientProxySession{cancel: cancel, cmd: command, done: make(chan error, 1)}
	go func() { session.done <- command.Wait() }()
	deadline := time.NewTimer(12 * time.Second)
	ticker := time.NewTicker(100 * time.Millisecond)
	defer deadline.Stop()
	defer ticker.Stop()
	for {
		select {
		case err := <-session.done:
			session.cancel()
			if err == nil {
				return nil, errors.New("Hysteria2 client exited before its proxy listener was ready")
			}
			return nil, fmt.Errorf("Hysteria2 client exited before its proxy listener was ready: %w", err)
		case <-deadline.C:
			session.Stop()
			return nil, errors.New("Hysteria2 client proxy listener did not become ready")
		case <-ticker.C:
			connection, err := net.DialTimeout("tcp", listen, 100*time.Millisecond)
			if err != nil {
				continue
			}
			_ = connection.Close()
			return session, nil
		}
	}
}

func ensureProxyListenerAvailable(listen string) error {
	listener, err := net.Listen("tcp", listen)
	if err != nil {
		return errors.New("configured proxy listener is already in use")
	}
	if err := listener.Close(); err != nil {
		return errors.New("configured proxy listener could not be released")
	}
	return nil
}
