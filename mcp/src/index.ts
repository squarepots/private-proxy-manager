import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';

type AgentEnvelope = {
  schema_version: number;
  command: string;
  success: boolean;
  code: string;
  data: unknown;
};

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..');
const productVersion = readFileSync(resolve(repoRoot, 'version.txt'), 'utf8').trim();
const agentScript = resolve(repoRoot, 'agent', 'ppm-agent.ps1');
const privateDirectory = process.env.PPM_PRIVATE_DIR ? resolve(process.env.PPM_PRIVATE_DIR) : resolve(repoRoot, 'private');
const pwsh = process.env.PPM_PWSH || 'pwsh';

const preflightOperationSchema = z.enum([
  'status',
  'audit',
  'add-server',
  'add-link',
  'add-route',
  'add-provider',
  'update-provider',
  'remove-provider',
  'add-profile',
  'update-profile',
  'remove-profile',
  'add-client-target',
  'update-client-target',
  'remove-client-target',
  'deploy-route',
  'render-client',
  'publish-subscription',
  'rotate-subscription-token',
  'backup',
  'migrate-route'
]);

const executableOperationSchema = z.enum([
  'status',
  'audit',
  'add-server',
  'add-link',
  'add-route',
  'add-provider',
  'update-provider',
  'remove-provider',
  'add-profile',
  'update-profile',
  'remove-profile',
  'add-client-target',
  'update-client-target',
  'remove-client-target',
  'deploy-route',
  'render-client',
  'publish-subscription'
]);

function runAgent(
  command: string,
  options: {
    operation?: string;
    target?: string;
    context?: Record<string, unknown>;
  } = {}
): Promise<AgentEnvelope> {
  return new Promise((resolvePromise, rejectPromise) => {
    const args = ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', agentScript, command, '-PrivateDirectory', privateDirectory];
    if (options.operation) args.push('-Operation', options.operation);
    if (options.target) args.push('-Target', options.target);
    if (options.context) args.push('-ContextStdin');

    const child = spawn(pwsh, args, { cwd: repoRoot, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let stdout = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.resume();

    child.on('error', () => rejectPromise(new Error('PPM agent process could not start.')));
    child.on('close', () => {
      try {
        const parsed = JSON.parse(stdout.trim()) as AgentEnvelope;
        if (!parsed || parsed.schema_version !== 1 || typeof parsed.success !== 'boolean') throw new Error('invalid envelope');
        resolvePromise(parsed);
      } catch {
        rejectPromise(new Error('PPM agent returned an invalid machine response.'));
      }
    });

    if (options.context) child.stdin.end(JSON.stringify(options.context));
    else child.stdin.end();
  });
}

function toolResult(result: AgentEnvelope) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(result) }], isError: !result.success };
}

function createServer(): McpServer {
  const server = new McpServer({ name: 'private-proxy-manager', version: productVersion });

  server.registerTool('ppm_capabilities', {
    description: 'Discover supported PPM operations, driver/rendering capability truth, executors, and authorization classes.',
    inputSchema: z.object({}),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async () => toolResult(await runAgent('capabilities')));

  server.registerTool('ppm_bootstrap', {
    description: 'Initialize clean local private PPM state. Idempotent for complete state and fail-closed for partial state.',
    inputSchema: z.object({}),
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async () => toolResult(await runAgent('bootstrap')));

  server.registerTool('ppm_context', {
    description: 'Read sanitized local project context without returning endpoints, paths, credentials, Provider URLs, or subscription tokens.',
    inputSchema: z.object({}),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async () => toolResult(await runAgent('context')));

  server.registerTool('ppm_drift', {
    description: 'Read sanitized desired-versus-observed route and ClientTarget-render drift. This does not change infrastructure.',
    inputSchema: z.object({}),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async () => toolResult(await runAgent('drift')));

  server.registerTool('ppm_preflight', {
    description: 'Evaluate required context, conflicts, effects, and authorization before mutation. Backup and migration may be preflighted here even though they are not generic one-shot MCP executions.',
    inputSchema: z.object({
      operation: preflightOperationSchema,
      target: z.string().min(1).optional(),
      context: z.record(z.string(), z.unknown()).optional()
    }),
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }
  }, async ({ operation, target, context }) => toolResult(await runAgent('preflight', { operation, target, context })));

  server.registerTool('ppm_execute', {
    description: 'Execute one supported repository-owned PPM operation after preflight passes. Backup/recovery use local secure password prompts; migration is composed; subscription-token rotation requires its dedicated authorized path.',
    inputSchema: z.object({
      operation: executableOperationSchema,
      target: z.string().min(1).optional(),
      context: z.record(z.string(), z.unknown()).optional()
    }),
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true }
  }, async ({ operation, target, context }) => toolResult(await runAgent('execute', { operation, target, context })));

  return server;
}

void serveStdio(createServer);
console.error('Private Proxy Manager MCP adapter running on local stdio.');
