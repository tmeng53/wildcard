import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

export const Me = z
  .strictObject({
    version: bodyVersion(1),
    userId: z.uuid().meta({ description: 'The signed-in member’s Supabase Auth user id.' }),
  })
  .openapi('Me');

/** `GET /me`: who the bearer token belongs to. The first route behind sign-in. */
export function me(deps: { readonly verifyToken: VerifyToken }) {
  const route = createRoute({
    method: 'get',
    path: '/me',
    operationId: 'getMe',
    summary: 'The signed-in member',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'Signed in', content: { 'application/json': { schema: Me } } },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });
  return new OpenAPIHono<SignedIn>().openapi(route, (c) =>
    c.json({ version: 1, userId: c.var.caller.userId } as const, 200),
  );
}
