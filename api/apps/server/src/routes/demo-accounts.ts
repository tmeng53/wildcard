import { randomUUID } from 'node:crypto';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { Admins } from '@wildcard/admins';
import { MemberId, type Members } from '@wildcard/members';

import { bodyVersion } from '../body-version.js';
import { UserId, type Accounts, type VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CharacterBody } from './character.js';

const memberId = z.uuid().meta({ description: 'The account’s member id.' });

export const DemoAccounts = z
  .strictObject({
    version: bodyVersion(1),
    accounts: z
      .array(
        z.strictObject({
          memberId,
          owner: z.boolean().meta({
            description:
              'Whether this is the admin’s own account, first in the list. The app switches back ' +
              'to it from the session it kept, never through a hand-off.',
          }),
          // The account's character, once it has saved a profile. Left out rather than null: the
          // Swift generator can't read a nullable reference.
          character: CharacterBody.optional(),
        }),
      )
      .meta({ description: 'The admin’s own account, then their demo accounts, oldest first.' }),
  })
  .openapi('DemoAccounts');

export const DemoAccount = z
  .strictObject({ version: bodyVersion(1), memberId })
  .openapi('DemoAccount');

export const DemoHandOff = z
  .strictObject({
    version: bodyVersion(1),
    refreshToken: z
      .string()
      .min(1)
      .meta({
        description:
          'A refresh token for the demo account’s new session: the app exchanges it with Auth as ' +
          'it renews any session, and is then signed in as that account.',
      }),
  })
  .openapi('DemoHandOff');

const signIn = {
  401: problem('No bearer token, or not a valid one'),
  403: problem(
    'The caller is neither an admin nor one of an admin’s demo accounts (`NOT_AN_ADMIN`)',
  ),
  503: problem('Sign-in can’t be checked, or Auth can’t be reached, right now'),
};

/** Where a demo account's email points: a domain we own, and nothing is ever mailed to it. */
const demoEmail = () => `demo-${randomUUID()}@demo.wildcardsquad.com`;

/**
 * An admin's demo accounts (Tracy, 2026-11-13): `GET` and `POST /me/demo-accounts` and
 * `POST /me/demo-accounts/{memberId}/hand-off`. Each is an ordinary member the admin switches to
 * from 设置 › 管理员, to dress, post and squad up as for promo pictures, so nothing done there
 * touches the admin's own account. The admin and any of their demo accounts may call them, so the
 * app switches on from a demo account too.
 */
export function demoAccounts(deps: {
  readonly verifyToken: VerifyToken;
  readonly admins: Pick<
    Admins,
    'demoOwner' | 'demoAccounts' | 'addDemoAccount' | 'requireDemoAccount'
  >;
  readonly accounts: Pick<Accounts, 'createUser' | 'handOff' | 'deleteUser'>;
  readonly members: Pick<Members, 'findProfile'>;
}) {
  const list = createRoute({
    method: 'get',
    path: '/me/demo-accounts',
    operationId: 'listDemoAccounts',
    summary: 'The admin’s demo accounts',
    description:
      'The admin’s own account, then each demo account they made, with its character. Signed in ' +
      'on a demo account, its admin’s.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The accounts',
        content: { 'application/json': { schema: DemoAccounts } },
      },
      ...signIn,
    },
  });

  const create = createRoute({
    method: 'post',
    path: '/me/demo-accounts',
    operationId: 'createDemoAccount',
    summary: 'Make a demo account',
    description:
      'A new, empty account for the admin to switch to: it signs up like anyone (character, ' +
      'squad) and signs in only through a hand-off. Each call makes another.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      201: { description: 'Made', content: { 'application/json': { schema: DemoAccount } } },
      ...signIn,
    },
  });

  const handOff = createRoute({
    method: 'post',
    path: '/me/demo-accounts/{memberId}/hand-off',
    operationId: 'handOffDemoAccount',
    summary: 'Switch to a demo account',
    description:
      'Starts a session on one of the admin’s demo accounts and returns its refresh token. ' +
      'Never for the admin’s own account, which the app keeps its own session for.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ memberId: z.uuid() }) },
    responses: {
      200: { description: 'Handed off', content: { 'application/json': { schema: DemoHandOff } } },
      400: problem('Not a valid member id'),
      404: problem('Not one of the admin’s demo accounts (`DEMO_ACCOUNT_NOT_FOUND`)'),
      ...signIn,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(list, async (c) => {
      const admin = await deps.admins.demoOwner(c.var.caller.userId);
      const ids: string[] = [admin, ...(await deps.admins.demoAccounts(admin))];
      const accounts = await Promise.all(
        ids.map(async (id) => {
          const profile = await deps.members.findProfile(MemberId.parse(id));
          const character = profile?.character ?? null;
          return {
            memberId: id,
            owner: id === admin,
            ...(character === null ? {} : { character }),
          };
        }),
      );
      return c.json({ version: 1 as const, accounts }, 200);
    })
    .openapi(create, async (c) => {
      const admin = await deps.admins.demoOwner(c.var.caller.userId);
      const member = await deps.accounts.createUser(demoEmail());
      try {
        await deps.admins.addDemoAccount(admin, member);
      } catch (error) {
        // Not recorded, so nobody could switch to it: don't leave it behind.
        await deps.accounts.deleteUser(member).catch(() => undefined);
        throw error;
      }
      return c.json({ version: 1 as const, memberId: member }, 201);
    })
    .openapi(handOff, async (c) => {
      const admin = await deps.admins.demoOwner(c.var.caller.userId);
      const member = await deps.admins.requireDemoAccount(admin, c.req.valid('param').memberId);
      const { refreshToken } = await deps.accounts.handOff(UserId.parse(member));
      return c.json({ version: 1 as const, refreshToken }, 200);
    });
}
