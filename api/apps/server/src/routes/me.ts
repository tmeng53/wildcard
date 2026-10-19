import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, TimeZone, type Members } from '@wildcard/members';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const profileFields = {
  timeZone: TimeZone.meta({
    description:
      'The member’s IANA time zone (iOS: `TimeZone.current.identifier`), for their weekly reset.',
    example: 'America/Los_Angeles',
  }),
};

/** The member's profile, as `PUT /me/profile` takes it and returns it. */
export const ProfileBody = z
  .strictObject({ version: bodyVersion(1), ...profileFields })
  .openapi('Profile');

export const Me = z
  .strictObject({
    version: bodyVersion(1),
    userId: z.uuid().meta({ description: 'The signed-in member’s Supabase Auth user id.' }),
    profile: z
      .strictObject(profileFields)
      .nullable()
      .meta({ description: 'Null until the member first saves one, right after signing up.' }),
  })
  .openapi('Me');

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `GET /me` and `PUT /me/profile`: the signed-in member and their own settings. */
export function me(deps: { readonly verifyToken: VerifyToken; readonly members: Members }) {
  const getMe = createRoute({
    method: 'get',
    path: '/me',
    operationId: 'getMe',
    summary: 'The signed-in member',
    description: 'Who the bearer token belongs to, and their profile once they have saved one.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'Signed in', content: { 'application/json': { schema: Me } } },
      ...unauthorized,
    },
  });
  const putProfile = createRoute({
    method: 'put',
    path: '/me/profile',
    operationId: 'putMyProfile',
    summary: 'Save the signed-in member’s profile',
    description:
      'Creates the profile on the first save, right after signing up, and replaces it after ' +
      'that. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: ProfileBody } } },
    },
    responses: {
      200: { description: 'Saved', content: { 'application/json': { schema: ProfileBody } } },
      400: problem('Not a valid profile, or a time zone that doesn’t exist (`TIME_ZONE_UNKNOWN`)'),
      ...jsonBodyFailures,
      ...unauthorized,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(getMe, async (c) => {
      const userId = c.var.caller.userId;
      const profile = await deps.members.findProfile(MemberId.parse(userId));
      return c.json({ version: 1, userId, profile: profile ?? null } as const, 200);
    })
    .openapi(putProfile, async (c) => {
      const { timeZone } = c.req.valid('json');
      const saved = await deps.members.saveProfile({
        member: MemberId.parse(c.var.caller.userId),
        profile: { timeZone },
      });
      return c.json({ version: 1, ...saved } as const, 200);
    });
}
