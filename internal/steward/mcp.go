package steward

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	routesteward "github.com/squarepots/route-steward"
)

type mcpOperationInput struct {
	Operation string         `json:"operation"`
	Target    string         `json:"target,omitempty"`
	Context   map[string]any `json:"context,omitempty"`
}

func NewMCPServer(privateDir string) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{Name: "route-steward", Version: routesteward.Version()}, nil)
	readOnly, notDestructive, closed, open := true, false, false, true
	add := func(name, description string, schema json.RawMessage, annotations *mcp.ToolAnnotations, handler func(context.Context, json.RawMessage) Envelope) {
		server.AddTool(&mcp.Tool{Name: name, Description: description, InputSchema: schema, Annotations: annotations}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			envelope := handler(ctx, request.Params.Arguments)
			body, err := json.Marshal(envelope)
			if err != nil {
				return nil, err
			}
			return &mcp.CallToolResult{Content: []mcp.Content{&mcp.TextContent{Text: string(body)}}, StructuredContent: envelope, IsError: !envelope.Success}, nil
		})
	}
	empty := json.RawMessage(`{"type":"object","additionalProperties":false}`)
	ro := &mcp.ToolAnnotations{ReadOnlyHint: readOnly, IdempotentHint: true, DestructiveHint: &notDestructive, OpenWorldHint: &closed}
	bootstrap := &mcp.ToolAnnotations{ReadOnlyHint: false, IdempotentHint: true, DestructiveHint: &notDestructive, OpenWorldHint: &closed}
	execute := &mcp.ToolAnnotations{ReadOnlyHint: false, IdempotentHint: false, DestructiveHint: &notDestructive, OpenWorldHint: &open}
	runSimple := func(command string) func(context.Context, json.RawMessage) Envelope {
		return func(ctx context.Context, _ json.RawMessage) Envelope {
			envelope, _ := RunRequest(ctx, Request{Command: command, PrivateDir: privateDir})
			return envelope
		}
	}
	add("route_steward_capabilities", "Discover supported Route Steward operations, drivers, effects, required context, and authorization classes.", empty, ro, runSimple("capabilities"))
	add("route_steward_bootstrap", "Initialize clean local private state. Complete state is idempotent and partial state fails closed.", empty, bootstrap, runSimple("bootstrap"))
	add("route_steward_context", "Read sanitized project context without returning endpoints, paths, credentials, Provider URLs, or subscription tokens.", empty, ro, runSimple("context"))
	add("route_steward_drift", "Read sanitized desired-versus-observed route and client-render drift.", empty, ro, runSimple("drift"))
	preflightOperations := []string{"status", "audit", "add-server", "add-link", "add-route", "add-provider", "update-provider", "remove-provider", "add-profile", "update-profile", "remove-profile", "add-client-target", "update-client-target", "remove-client-target", "deploy-route", "render-client", "publish-subscription", "rotate-subscription-token", "backup", "migrate-route"}
	executableOperations := []string{"status", "audit", "add-server", "add-link", "add-route", "add-provider", "update-provider", "remove-provider", "add-profile", "update-profile", "remove-profile", "add-client-target", "update-client-target", "remove-client-target", "deploy-route", "render-client", "publish-subscription"}
	add("route_steward_preflight", "Evaluate context, conflicts, effects, and authorization before an operation.", mcpOperationSchema(preflightOperations), ro, func(ctx context.Context, raw json.RawMessage) Envelope {
		var input mcpOperationInput
		if err := json.Unmarshal(raw, &input); err != nil {
			return invalidMCPEnvelope("preflight", err)
		}
		envelope, _ := RunRequest(ctx, Request{Command: "preflight", Operation: input.Operation, Target: input.Target, Context: input.Context, PrivateDir: privateDir})
		return envelope
	})
	add("route_steward_execute", "Execute one supported bounded operation after preflight. Credential rotation and secure-prompt recovery use dedicated local paths.", mcpOperationSchema(executableOperations), execute, func(ctx context.Context, raw json.RawMessage) Envelope {
		var input mcpOperationInput
		if err := json.Unmarshal(raw, &input); err != nil {
			return invalidMCPEnvelope("execute", err)
		}
		allowed := map[string]bool{}
		for _, operation := range executableOperations {
			allowed[operation] = true
		}
		if !allowed[input.Operation] {
			envelope, _ := SanitizedFailure("execute", fmt.Errorf("operation requires a dedicated local workflow"))
			return envelope
		}
		envelope, _ := RunRequest(ctx, Request{Command: "execute", Operation: input.Operation, Target: input.Target, Context: input.Context, PrivateDir: privateDir})
		return envelope
	})
	return server
}

func mcpOperationSchema(operations []string) json.RawMessage {
	schema, _ := json.Marshal(map[string]any{
		"type":                 "object",
		"additionalProperties": false,
		"required":             []string{"operation"},
		"properties": map[string]any{
			"operation": map[string]any{"type": "string", "enum": operations},
			"target":    map[string]any{"type": "string", "minLength": 1},
			"context":   map[string]any{"type": "object", "additionalProperties": true},
		},
	})
	return schema
}

func RunMCP(ctx context.Context, privateDir string) error {
	return NewMCPServer(privateDir).Run(ctx, &mcp.StdioTransport{})
}

func invalidMCPEnvelope(command string, err error) Envelope {
	envelope, _ := SanitizedFailure(command, err)
	return envelope
}
