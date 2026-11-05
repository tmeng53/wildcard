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
    settings: z
      .partialRecord(PushTopic, z.boolean())
      // A save that names no switch is a mistake, not a save of nothing.
      .refine((settings) => Object.keys(settings).length > 0, 'names no switch')
      .meta({
        description:
          'Each kind of push, on or off; all on until the member turns one off. A save may leave ' +
          'switches out, which keep what they were; a read has every one. ' +
          '`dailyProgress`: the one push a day at 6pm with the squad’s week and what teammates ' +
          'sent them. `coach`: what the squad’s coach says to the member (its replies, answers ' +
          'and morning note), sent silently; the bell keeps them whatever this is.',
        example: { dailyProgress: true, coach: true },
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
      400: problem('Not a valid body'),
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
