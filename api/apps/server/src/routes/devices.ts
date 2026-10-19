import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { DeviceToken, MemberId, PushEnvironment, type Push } from '@wildcard/push';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

// The token goes in the body, never the path, so it stays out of request logs.
const token = DeviceToken.meta({
  description: 'The APNs device token iOS gave the app, hex-encoded.',
  example: 'a1'.repeat(32),
});

/** A phone, as `PUT /me/devices` takes it and returns it. */
export const Device = z
  .strictObject({
    version: bodyVersion(1),
    token,
    environment: PushEnvironment.meta({
      description:
        'Which APNs servers the token is for: `sandbox` in a build run from Xcode, ' +
        '`production` in TestFlight and the App Store.',
    }),
  })
  .openapi('Device');

/** The phone to stop pushing to, as `POST /me/devices/remove` takes it. */
export const DeviceRemoval = z
  .strictObject({ version: bodyVersion(1), token })
  .openapi('DeviceRemoval');

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `PUT /me/devices` and `POST /me/devices/remove`: the phones the member gets pushes on. */
export function devices(deps: { readonly verifyToken: VerifyToken; readonly push: Push }) {
  const register = createRoute({
    method: 'put',
    path: '/me/devices',
    operationId: 'registerMyDevice',
    summary: 'Get push notifications on this phone',
    description:
      'The app calls this whenever iOS hands it a device token (every launch, once ' +
      'notifications are allowed). Safe to repeat. A token names one install, so a phone ' +
      'someone else signed in on before moves to the caller.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: Device } } },
    },
    responses: {
      200: { description: 'Registered', content: { 'application/json': { schema: Device } } },
      400: problem('Not a device token, or not a valid body'),
      ...jsonBodyFailures,
      ...unauthorized,
    },
  });
  const remove = createRoute({
    method: 'post',
    path: '/me/devices/remove',
    operationId: 'removeMyDevice',
    summary: 'Stop push notifications on this phone',
    description: 'For signing out. Safe to repeat, and does nothing for a phone that isn’t yours.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: DeviceRemoval } } },
    },
    responses: {
      204: { description: 'Stopped' },
      400: problem('Not a device token'),
      ...jsonBodyFailures,
      ...unauthorized,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(register, async (c) => {
      const device = c.req.valid('json');
      await deps.push.registerDevice({
        member: MemberId.parse(c.var.caller.userId),
        device: { token: device.token, environment: device.environment },
      });
      return c.json(device, 200);
    })
    .openapi(remove, async (c) => {
      await deps.push.unregisterDevice({
        member: MemberId.parse(c.var.caller.userId),
        token: c.req.valid('json').token,
      });
      return c.body(null, 204);
    });
}
