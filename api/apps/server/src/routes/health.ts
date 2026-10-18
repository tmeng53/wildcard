import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { sql } from 'kysely';

import { bodyVersion } from '../body-version.js';
import { DatabaseUnavailableError } from '../errors.js';
import type { Database } from '../ports.js';
import { problem } from '../problem.js';

export const Health = z
  .strictObject({ version: bodyVersion(1), status: z.literal('ok') })
  .openapi('Health');

const route = createRoute({
  method: 'get',
  path: '/health',
  operationId: 'getHealth',
  summary: 'Whether the API can reach its database',
  responses: {
    200: { description: 'Ready', content: { 'application/json': { schema: Health } } },
    503: problem('The database is unreachable'),
  },
});

/** `GET /health`, for Cloud Run's probes and for the app to tell "offline" from "down". */
export function health(deps: { readonly db: Database }) {
  return new OpenAPIHono().openapi(route, async (c) => {
    try {
      await sql`select 1`.execute(deps.db);
    } catch (cause) {
      throw new DatabaseUnavailableError({ cause });
    }
    return c.json({ version: 1, status: 'ok' } as const, 200);
  });
}
