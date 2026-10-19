import {
  McpServer,
  createMcpHandler,
  getOAuthProtectedResourceMetadataUrl,
  type CallToolResult,
} from '@modelcontextprotocol/server';
import { AdminId, type Admins } from '@wildcard/admins';
import { HTTP_STATUS, isAppError } from '@wildcard/errors';
import { Hono } from 'hono';

import { AdminSignInRequiredError, AuthTokenMissingError } from '../errors.js';
import type { Log } from '../log.js';
import type { Database, VerifyToken } from '../ports.js';
import { problemResponse } from '../problem.js';
import { bearerToken } from '../require-caller.js';
import type { AdminTool } from './admin-tool.js';

export interface AdminMcpDependencies {
  readonly db: Database;
  readonly verifyToken: VerifyToken;
  /** The admin list and log, working on `db` or on a transaction of it. */
  readonly admins: (db: Database) => Admins;
  /** The tools, working on `db` or on a transaction of it. */
  readonly tools: (db: Database) => readonly AdminTool[];
  /** Where clients reach this API; the MCP server is at `/mcp` under it. */
  readonly publicUrl: URL;
  /** The OAuth 2.1 authorization server that signs admins in (Supabase Auth's issuer). */
  readonly authorizationServer: URL;
  readonly log: Log;
}

/**
 * The admin MCP server, at `/mcp`: tools an admin uses from an MCP client (Claude Code,
 * claude.ai) to manage the app. Clients find how to sign in from the 401's
 * `WWW-Authenticate` header and the protected resource metadata it points to, then sign the
 * admin in through the authorization server with OAuth 2.1.
 * https://modelcontextprotocol.io/specification/latest/basic/authorization
 */
export function adminMcp(deps: AdminMcpDependencies) {
  const admins = deps.admins(deps.db);
  const tools = deps.tools(deps.db);
  const resource = new URL('/mcp', deps.publicUrl);
  const metadataUrl = getOAuthProtectedResourceMetadataUrl(resource);
  // RFC 9728 protected resource metadata. https://www.rfc-editor.org/rfc/rfc9728
  const metadata = {
    resource: resource.href,
    authorization_servers: [deps.authorizationServer.href.replace(/\/$/, '')],
    bearer_methods_supported: ['header'],
    resource_name: 'Wildcard admin',
  };

  const handler = createMcpHandler(
    ({ authInfo }) => {
      // Set below, after the admin check; a request never reaches the handler without it.
      const admin = AdminId.parse(authInfo?.extra?.admin);
      const server = new McpServer({ name: 'wildcard-admin', version: '1.0.0' });
      for (const tool of tools) {
        server.registerTool(
          tool.name,
          {
            title: tool.title,
            description: tool.description,
            inputSchema: tool.input,
            annotations: { readOnlyHint: !tool.changes, destructiveHint: false },
          },
          async (input): Promise<CallToolResult> => {
            try {
              const result = tool.changes
                ? await runLogged(deps, { name: tool.name, input, admin })
                : await tool.run(input, { admin });
              return { content: [{ type: 'text', text: JSON.stringify(result) }] };
            } catch (error) {
              return toolFailure(error, { tool: tool.name, log: deps.log });
            }
          },
        );
      }
      return server;
    },
    {
      onerror: (error) => {
        deps.log.error('admin MCP request failed', { error });
      },
    },
  );

  const app = new Hono();
  app.get(new URL(metadataUrl).pathname, (c) => c.json(metadata));
  app.all('/mcp', async (c) => {
    let authInfo;
    try {
      const token = bearerToken(c.req.header('authorization'));
      const caller = await deps.verifyToken(token);
      if (caller.oauthClient === undefined) throw new AdminSignInRequiredError();
      const admin = await admins.requireAdmin(caller.userId);
      authInfo = { token, clientId: caller.oauthClient, scopes: [], extra: { admin } };
    } catch (error) {
      if (!isAppError(error) || error.status !== 'UNAUTHENTICATED') throw error;
      // Tells the MCP client where to sign in. A missing token gets no `error`, per RFC 6750.
      const response = problemResponse(error);
      const invalid = error instanceof AuthTokenMissingError ? '' : 'error="invalid_token", ';
      response.headers.set(
        'www-authenticate',
        `Bearer ${invalid}resource_metadata="${metadataUrl}"`,
      );
      return response;
    }
    return handler.fetch(c.req.raw, { authInfo });
  });
  return app;
}

/** A tool call that failed: our errors say why; anything else is logged and stays private. */
function toolFailure(
  error: unknown,
  { tool, log }: { readonly tool: string; readonly log: Log },
): CallToolResult {
  if (isAppError(error) && HTTP_STATUS[error.status] < 500) {
    return {
      isError: true,
      content: [{ type: 'text', text: `${error.reason}: ${error.message}` }],
    };
  }
  log.error('admin tool failed', { tool, error });
  return {
    isError: true,
    content: [{ type: 'text', text: 'The tool failed. Try again shortly.' }],
  };
}

/**
 * Runs a tool that changes something and logs the call in one transaction, so a change is
 * never kept without its log row, nor logged without the change.
 */
function runLogged(
  deps: AdminMcpDependencies,
  call: {
    readonly name: AdminTool['name'];
    readonly input: Record<string, unknown>;
    readonly admin: AdminId;
  },
) {
  const { name, input, admin } = call;
  return deps.db.transaction().execute(async (trx) => {
    const tool = deps.tools(trx).find((each) => each.name === name);
    if (tool === undefined) throw new Error(`No admin tool ${name} in the transaction`);
    const result = await tool.run(input, { admin });
    await deps.admins(trx).logChange({ admin, tool: name, arguments: input });
    return result;
  });
}
