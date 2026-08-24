package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	routesteward "github.com/squarepots/route-steward"
	"github.com/squarepots/route-steward/internal/steward"
)

func main() { os.Exit(run()) }

func run() int {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: route-steward <capabilities|bootstrap|context|drift|health|preflight|execute|mcp|backup|recover|version>")
		return 2
	}
	command := os.Args[1]
	if command == "version" {
		fmt.Println(routesteward.Version())
		return 0
	}
	defaults := defaultPrivateDir()
	switch command {
	case "health":
		fs := newFlags("health")
		privateDir := fs.String("private-dir", defaults, "private state directory")
		target := fs.String("target", "", "deployed Route id")
		includePublicIP := fs.Bool("include-public-ip", false, "include the observed public IP in this response")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return 2
		}
		if *target == "" {
			fmt.Fprintln(os.Stderr, "--target is required")
			return 2
		}
		envelope, exit := steward.RunRequest(context.Background(), steward.Request{Command: "health", Target: *target, Context: map[string]any{"include_public_ip": *includePublicIP}, PrivateDir: absolute(*privateDir)})
		writeEnvelope(envelope)
		return exit
	case "mcp":
		fs := newFlags("mcp")
		privateDir := fs.String("private-dir", defaults, "private state directory")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return 2
		}
		if err := steward.RunMCP(context.Background(), absolute(*privateDir)); err != nil {
			fmt.Fprintln(os.Stderr, "Route Steward MCP failed locally.")
			return 1
		}
		return 0
	case "backup":
		fs := newFlags("backup")
		privateDir := fs.String("private-dir", defaults, "private state directory")
		sevenZip := fs.String("seven-zip", "", "7-Zip executable")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return 2
		}
		state, err := steward.LoadState(absolute(*privateDir))
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		archive, err := steward.CreateRecoveryArchive(state, *sevenZip)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		body, _ := json.Marshal(map[string]any{"schema_version": 1, "command": "backup", "success": true, "code": "ok", "data": map[string]any{"archive": archive, "verified": true, "remote_changed": false}})
		fmt.Println(string(body))
		return 0
	case "recover":
		fs := newFlags("recover")
		privateDir := fs.String("private-dir", defaults, "new private state directory")
		archive := fs.String("archive", "", "encrypted recovery archive")
		sevenZip := fs.String("seven-zip", "", "7-Zip executable")
		if err := fs.Parse(os.Args[2:]); err != nil {
			return 2
		}
		if *archive == "" {
			fmt.Fprintln(os.Stderr, "--archive is required")
			return 2
		}
		result, err := steward.RestoreRecoveryArchive(*archive, absolute(*privateDir), *sevenZip)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		body, _ := json.Marshal(map[string]any{"schema_version": 1, "command": "recover", "success": true, "code": "ok", "data": result})
		fmt.Println(string(body))
		return 0
	}
	fs := newFlags(command)
	privateDir := fs.String("private-dir", defaults, "private state directory")
	operation := fs.String("operation", "", "operation id")
	target := fs.String("target", "", "target id")
	contextJSON := fs.String("context-json", "", "operation context JSON")
	contextStdin := fs.Bool("context-stdin", false, "read operation context from stdin")
	approved := fs.Bool("approved", false, "explicit current approval for guarded credential changes")
	if err := fs.Parse(os.Args[2:]); err != nil {
		return 2
	}
	contextValue, err := readContext(*contextJSON, *contextStdin)
	if err != nil {
		envelope, exit := steward.SanitizedFailure(command, err)
		writeEnvelope(envelope)
		return exit
	}
	envelope, exit := steward.RunRequest(context.Background(), steward.Request{Command: command, Operation: *operation, Target: *target, Context: contextValue, PrivateDir: absolute(*privateDir), Approved: *approved})
	writeEnvelope(envelope)
	return exit
}

func newFlags(name string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	return fs
}
func defaultPrivateDir() string {
	if value := os.Getenv("RST_PRIVATE_DIR"); value != "" {
		return value
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "private"
	}
	return filepath.Join(cwd, "private")
}
func absolute(path string) string {
	value, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return value
}
func readContext(raw string, stdin bool) (map[string]any, error) {
	if raw != "" && stdin {
		return nil, fmt.Errorf("use either --context-json or --context-stdin")
	}
	if stdin {
		body, err := io.ReadAll(os.Stdin)
		if err != nil {
			return nil, err
		}
		raw = string(body)
	}
	if raw == "" {
		return nil, nil
	}
	var value map[string]any
	if err := json.Unmarshal([]byte(raw), &value); err != nil {
		return nil, fmt.Errorf("operation context is not valid JSON")
	}
	return value, nil
}
func writeEnvelope(envelope steward.Envelope) {
	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(envelope)
}
