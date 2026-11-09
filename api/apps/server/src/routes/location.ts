import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, type Weather } from '@wildcard/weather';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** Roughly where the member is, as `PUT /me/location` takes it and answers it. */
export const MemberLocation = z
  .strictObject({
    version: bodyVersion(1),
    latitude: z.number().min(-90).max(90).meta({ example: 40.7 }),
    longitude: z.number().min(-180).max(180).meta({ example: -74 }),
  })
  .meta({
    description:
      'The phone’s approximate location. The server keeps only its 0.1° cell (about 11 km), ' +
      'and only the latest, to look up the weather there for the squad’s coach. Squadmates ' +
      'and the AI never see it.',
  })
  .openapi('MemberLocation');

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `PUT` and `DELETE /me/location`: where the member roughly is, for the coach's weather. */
export function location(deps: { readonly verifyToken: VerifyToken; readonly weather: Weather }) {
  const save = createRoute({
    method: 'put',
    path: '/me/location',
    operationId: 'saveMyLocation',
    summary: 'Say roughly where the member is',
    description:
      'The app sends the approximate location iOS gives it when it opens, while the member ' +
      'allows it. Replaces the one before. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: MemberLocation } } },
    },
    responses: {
      200: {
        description: 'Kept, as the cell the server keeps',
        content: { 'application/json': { schema: MemberLocation } },
      },
      400: problem('Not a valid body'),
      ...jsonBodyFailures,
      ...unauthorized,
    },
  });
  const forget = createRoute({
    method: 'delete',
    path: '/me/location',
    operationId: 'forgetMyLocation',
    summary: 'Forget where the member is',
    description: 'For when the member stops allowing location. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      204: { description: 'Forgotten' },
      ...unauthorized,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(save, async (c) => {
      const { latitude, longitude } = c.req.valid('json');
      const kept = await deps.weather.savePlace(MemberId.parse(c.var.caller.userId), {
        latitude,
        longitude,
      });
      return c.json({ version: 1 as const, ...kept }, 200);
    })
    .openapi(forget, async (c) => {
      await deps.weather.forgetPlace(MemberId.parse(c.var.caller.userId));
      return c.body(null, 204);
    });
}
