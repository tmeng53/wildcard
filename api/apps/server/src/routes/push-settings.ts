import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, PushTopic, type Push } from '@wildcard/push';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** Every kind of push with its switch, as `GET` and `PUT /me/push-settings` carry them. */
export const PushSettings = z
  .strictObject({
    version: bodyVersion(1),
    settings: z.record(PushTopic, z.boolean()).meta({
      description:
        'Each kind of push, on or off; all on until the member turns one off. ' +
        '`dailyProgress`: the one push a day at 6pm with the squad’s week and what teammates ' +
        'sent them.',
      example: { dailyProgress: true },
    }),
  })
  .openapi('PushSettings');

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `GET` and `PUT /me/push-settings`: which kinds of push the member gets. */
export function pushSettings(deps: { readonly verifyToken: VerifyToken; readonly push: Push }) {
  const read = createRoute({
    method: 'get',
    path: '/me/push-settings',
    operationId: 'getMyPushSettings',
    summary: 'Which kinds of push the member gets',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'Every switch',
        content: { 'application/json': { schema: PushSettings } },
      },
      ...unauthorized,
    },
  });
  const save = createRoute({
    method: 'put',
    path: '/me/push-settings',
    operationId: 'saveMyPushSettings',
    summary: 'Turn kinds of push on or off',
    description: 'Takes every switch at once. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: PushSettings } } },
    },
    responses: {
      200: { description: 'Saved', content: { 'application/json': { schema: PushSettings } } },
      400: problem('Not a valid body, or a switch missing'),
      ...unauthorized,
      ...jsonBodyFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const settings = await deps.push.settingsOf(MemberId.parse(c.var.caller.userId));
      return c.json({ version: 1 as const, settings }, 200);
    })
    .openapi(save, async (c) => {
      const settings = await deps.push.saveSettings({
        member: MemberId.parse(c.var.caller.userId),
        settings: c.req.valid('json').settings,
      });
      return c.json({ version: 1 as const, settings }, 200);
    });
}
