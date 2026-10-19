import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, TimeZone, type Members } from '@wildcard/members';

import { bodyVersion } from '../body-version.js';
import { deleteAccount, type DeleteAccountDependencies } from '../flows/delete-account.js';
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

/** What `DELETE /me` takes. */
export const AccountDeletion = z
  .strictObject({
    version: bodyVersion(1),
    appleAuthorizationCode: z
      .string()
      .min(1)
      .max(2000)
      .optional()
      .meta({
        description:
          'For a member who signed in with Apple: a fresh `authorizationCode` from Sign in with ' +
          'Apple (codes last 5 minutes), so the API can revoke the app’s Apple tokens. ' +
          'Required for an account that signs in with Apple once revocation is set up.',
      }),
  })
  .openapi('AccountDeletion');

const unauthorized = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET /me`, `PUT /me/profile` and `DELETE /me`: the signed-in member, their own settings, and
 * deleting their account.
 */
export function me(
  deps: {
    readonly verifyToken: VerifyToken;
    readonly members: Members;
  } & DeleteAccountDependencies,
) {
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

  const deleteMe = createRoute({
    method: 'delete',
    path: '/me',
    operationId: 'deleteMe',
    summary: 'Delete the signed-in member’s account',
    description:
      'Deletes the account and everything that is the member’s: profile, check-ins, photos and ' +
      'squad memberships (squads they made stay with the other members), and revokes Sign in ' +
      'with Apple when given a code. Can’t be undone. The session is checked with the sign-in ' +
      'provider, so a signed-out token is refused even before it expires. Safe to repeat after ' +
      'a failure. Afterwards this route refuses the token; other routes accept it until it ' +
      'expires, so the app signs out.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.accounts.verifySession)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: AccountDeletion } } },
    },
    responses: {
      204: { description: 'Deleted' },
      400: problem(
        'Not a valid request, an Apple code Apple refused (`APPLE_AUTHORIZATION_CODE_INVALID`), ' +
          'or no Apple code for an account that signs in with Apple ' +
          '(`APPLE_AUTHORIZATION_CODE_REQUIRED`)',
      ),
      401: problem('No bearer token, or not a current sign-in'),
      ...jsonBodyFailures,
      503: problem('Sign-in, photo storage or Apple can’t be reached right now'),
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
    })
    .openapi(deleteMe, async (c) => {
      const { appleAuthorizationCode } = c.req.valid('json');
      await deleteAccount(deps, { member: c.var.caller.userId, appleAuthorizationCode });
      return c.body(null, 204);
    });
}
