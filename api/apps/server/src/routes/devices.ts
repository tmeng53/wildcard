import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { DeviceToken, MemberId, PushEnvironment, type Push } from '@wildcard/push';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** A phone, as `PUT /me/devices/{token}` takes it and returns it. */
export const DeviceBody = z
  .strictObject({
    version: bodyVersion(1),
    environment: PushEnvironment.meta({
      description:
        'Which APNs servers the token is for: `sandbox` in a build run from Xcode, ' +
        '`production` in TestFlight and the App Store.',
    }),
  })
  .openapi('Device');

const params = z.strictObject({
  token: DeviceToken.meta({
    description: 'The APNs device token iOS gave the app, hex-encoded.',
    example: 'a1'.repeat(32),
  }),
});

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `PUT` and `DELETE /me/devices/{token}`: the phones the signed-in member gets pushes on. */
export function devices(deps: { readonly verifyToken: VerifyToken; readonly push: Push }) {
  const register = createRoute({
    method: 'put',
    path: '/me/devices/{token}',
    operationId: 'registerMyDevice',
    summary: 'Get push notifications on this phone',
    description:
      'The app calls this whenever iOS hands it a device token (every launch, once ' +
      'notifications are allowed). Safe to repeat; a phone someone else used moves to the caller.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: DeviceBody } } },
    },
    responses: {
      200: { description: 'Registered', content: { 'application/json': { schema: DeviceBody } } },
      400: problem('Not a device token, or not a valid body'),
      ...unauthorized,
    },
  });
  const unregister = createRoute({
    method: 'delete',
    path: '/me/devices/{token}',
    operationId: 'unregisterMyDevice',
    summary: 'Stop push notifications on this phone',
    description: 'For signing out. Safe to repeat, and does nothing for a phone that isn’t yours.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      204: { description: 'Stopped' },
      400: problem('Not a device token'),
      ...unauthorized,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(register, async (c) => {
      const { environment } = c.req.valid('json');
      await deps.push.registerDevice({
        member: MemberId.parse(c.var.caller.userId),
        device: { token: c.req.valid('param').token, environment },
      });
      return c.json({ version: 1, environment } as const, 200);
    })
    .openapi(unregister, async (c) => {
      await deps.push.unregisterDevice({
        member: MemberId.parse(c.var.caller.userId),
        token: c.req.valid('param').token,
      });
      return c.body(null, 204);
    });
}
