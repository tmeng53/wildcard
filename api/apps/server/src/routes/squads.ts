import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  InviteCode,
  InviteCodeUnknownError,
  MemberId,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  SquadId,
  SquadName,
  type Squad as SquadRecord,
  type Squads,
} from '@wildcard/squads';
import type { Members } from '@wildcard/members';

import { bodyVersion } from '../body-version.js';
import type { RateLimit, VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { rateLimited } from '../rate-limited.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { LookBody } from './character.js';

const inviteCodeField = z.string().meta({
  description:
    'Members share it to invite friends; an invite link carries it. 8 letters and digits, ' +
    'without 0, O, 1, I or L.',
  example: 'K7M2QX9P',
});

/** A squad, as its members see it. */
export const Squad = z
  .strictObject({
    version: bodyVersion(1),
    id: z.uuid(),
    name: z.string().meta({ description: 'The squad’s name, as its creator typed it, trimmed.' }),
    inviteCode: inviteCodeField,
    createdAt: z.iso.datetime().meta({ description: 'When it was created, in UTC.' }),
    members: z
      .array(
        z.strictObject({
          userId: z.uuid().meta({ description: 'The member’s Supabase Auth user id.' }),
          joinedAt: z.iso.datetime().meta({ description: 'When they joined, in UTC.' }),
        }),
      )
      .meta({
        description: `Who is in it now, the earliest to join first: 1 to ${String(SQUAD_MEMBER_LIMIT)}.`,
      }),
  })
  .openapi('Squad');

const SquadList = z
  .strictObject({
    version: bodyVersion(1),
    squads: z.array(Squad).meta({
      description: `The member’s squads, the earliest joined first: at most ${String(SQUADS_PER_MEMBER)}.`,
    }),
  })
  .openapi('SquadList');

const NewSquad = z.strictObject({ version: bodyVersion(1), name: SquadName }).openapi('NewSquad');

const SquadInvite = z
  .strictObject({
    version: bodyVersion(1),
    name: z.string().meta({ description: 'The squad’s name.' }),
    memberCount: z.int().meta({ description: 'How many members it has now.' }),
    full: z.boolean().meta({
      description: `True when it has ${String(SQUAD_MEMBER_LIMIT)} members and can’t take more.`,
    }),
    joined: z.boolean().meta({ description: 'True when the caller is in it already.' }),
  })
  .openapi('SquadInvite');

const PublicSquadInvite = z
  .strictObject({
    version: bodyVersion(1),
    name: z.string().meta({ description: 'The squad’s name.' }),
    memberCount: z.int().meta({ description: 'How many members it has now.' }),
    full: z.boolean().meta({
      description: `True when it has ${String(SQUAD_MEMBER_LIMIT)} members and can’t take more.`,
    }),
    looks: z.array(LookBody).meta({
      description:
        'The members’ characters, the earliest to join first, for the page to show the squad. ' +
        'Members who haven’t made theirs yet are left out. No names or ids.',
    }),
  })
  .openapi('PublicSquadInvite');

function wire(squad: SquadRecord) {
  return {
    version: 1 as const,
    id: squad.id,
    name: squad.name,
    inviteCode: squad.inviteCode,
    createdAt: squad.createdAt.toISOString(),
    members: squad.members.map(({ member, joinedAt }) => ({
      userId: member,
      joinedAt: joinedAt.toISOString(),
    })),
  };
}

/** An invite code as typed or carried by a link. One that can't be a code is no squad's code. */
function inviteCodeOf(typed: string): InviteCode {
  const code = InviteCode.safeParse(typed);
  if (!code.success) throw new InviteCodeUnknownError();
  return code.data;
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};
const limitReached = `the member is in ${String(SQUADS_PER_MEMBER)} squads already (\`SQUAD_LIMIT_REACHED\`)`;
const noConsent = 'the member hasn’t agreed to the current AI terms (`AI_CONSENT_REQUIRED`)';

/** What routes anyone can call without signing in need: a rate limit per client. */
export interface PublicRoutes {
  /** How many of our proxies add to `X-Forwarded-For`; see `clientAddress`. */
  readonly proxyHops: number;
  /** Invite lookups by the web invite page, per client address. */
  readonly inviteLookups: RateLimit;
}

/**
 * Squads: create one with a name, preview and join one by invite code, list mine, read one, and
 * leave. A squad is never deleted; its members leave.
 */
export function squads(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly members: Members;
  readonly publicRoutes: PublicRoutes;
}) {
  const squadParams = z.strictObject({ squadId: SquadId });
  // Any text: one that can't be a code answers 404 like an unknown one, so the app has one case.
  const inviteParams = z.strictObject({ inviteCode: z.string().meta({ example: 'K7M2QX9P' }) });
  const squadResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: Squad } },
  });

  const listMine = createRoute({
    method: 'get',
    path: '/me/squads',
    operationId: 'listMySquads',
    summary: 'The signed-in member’s squads',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The squads', content: { 'application/json': { schema: SquadList } } },
      ...signedInFailures,
    },
  });

  const create = createRoute({
    method: 'put',
    path: '/squads/{squadId}',
    operationId: 'createSquad',
    summary: 'Create a squad',
    description:
      'With only a name; the caller is its first member, and needs a current AI consent ' +
      '(`GET /me/ai-consent`). The app makes the id, so a create can ' +
      'be retried: the same squad again answers 200, another name or member under that id 409.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: NewSquad } } },
    },
    responses: {
      200: squadResponse('Already created: this was a retry'),
      201: squadResponse('Created'),
      400: problem(`Not a valid name, ${limitReached}, or ${noConsent}`),
      409: problem('The id holds another squad (`SQUAD_ID_CONFLICT`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const find = createRoute({
    method: 'get',
    path: '/squads/{squadId}',
    operationId: 'getSquad',
    summary: 'A squad and who is in it',
    description: 'Only for its members.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      200: squadResponse('The squad'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const leave = createRoute({
    method: 'delete',
    path: '/squads/{squadId}/members/me',
    operationId: 'leaveSquad',
    summary: 'Leave a squad',
    description:
      'Their check-ins leave the squad’s list with them. Safe to repeat: leaving a squad the ' +
      'member isn’t in changes nothing.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      204: { description: 'Not in the squad any more' },
      400: problem('Not a valid squad id'),
      ...signedInFailures,
    },
  });

  const preview = createRoute({
    method: 'get',
    path: '/squad-invites/{inviteCode}',
    operationId: 'getSquadInvite',
    summary: 'The squad an invite code belongs to',
    description:
      'What the join screen shows before joining. Case, spaces and dashes in the code don’t ' +
      'matter.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: inviteParams },
    responses: {
      200: { description: 'The squad', content: { 'application/json': { schema: SquadInvite } } },
      404: problem('No squad has this code (`INVITE_CODE_UNKNOWN`)'),
      ...signedInFailures,
    },
  });

  const publicPreview = createRoute({
    method: 'get',
    path: '/public/squad-invites/{inviteCode}',
    operationId: 'getPublicSquadInvite',
    summary: 'The squad an invite code belongs to, for anyone',
    description:
      'What the web invite page shows before the app is installed: no sign-in, so only the ' +
      'name, the size, whether it is full and the members’ characters; no names or ids, nothing ' +
      'that says who is in it. Limited per client address. Case, spaces and dashes in the code ' +
      'don’t matter.',
    middleware: [
      rateLimited(deps.publicRoutes.inviteLookups, deps.publicRoutes.proxyHops),
    ] as const,
    request: { params: inviteParams },
    responses: {
      200: {
        description: 'The squad',
        headers: {
          'Cache-Control': {
            description: '`no-store`: the size and looks change as people join.',
            schema: { type: 'string' },
          },
        },
        content: { 'application/json': { schema: PublicSquadInvite } },
      },
      404: problem('No squad has this code (`INVITE_CODE_UNKNOWN`)'),
      429: {
        ...problem('Too many lookups from this address (`REQUESTS_TOO_FREQUENT`)'),
        headers: {
          'Retry-After': {
            description: 'Seconds until lookups from this address are taken again.',
            schema: { type: 'integer' },
          },
        },
      },
    },
  });

  const join = createRoute({
    method: 'post',
    path: '/squad-invites/{inviteCode}/accept',
    operationId: 'joinSquad',
    summary: 'Join a squad by invite code',
    description:
      'The member needs a current AI consent (`GET /me/ai-consent`). Safe to repeat: joining a ' +
      'squad the member is in answers 200 with it.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: inviteParams },
    responses: {
      200: squadResponse('Already in it'),
      201: squadResponse('Joined'),
      400: problem(
        `The squad has ${String(SQUAD_MEMBER_LIMIT)} members (\`SQUAD_FULL\`), ${limitReached}, or ${noConsent}`,
      ),
      404: problem('No squad has this code (`INVITE_CODE_UNKNOWN`)'),
      ...signedInFailures,
    },
  });

  const caller = (userId: string) => MemberId.parse(userId);

  const signedInRoutes = new OpenAPIHono<SignedIn>()
    .openapi(listMine, async (c) => {
      const mine = await deps.squads.listMine(caller(c.var.caller.userId));
      return c.json({ version: 1 as const, squads: mine.map(wire) }, 200);
    })
    .openapi(create, async (c) => {
      const { squad, created } = await deps.squads.create({
        id: c.req.valid('param').squadId,
        creator: caller(c.var.caller.userId),
        name: c.req.valid('json').name,
      });
      return created ? c.json(wire(squad), 201) : c.json(wire(squad), 200);
    })
    .openapi(find, async (c) => {
      const squad = await deps.squads.find({
        squad: c.req.valid('param').squadId,
        viewer: caller(c.var.caller.userId),
      });
      return c.json(wire(squad), 200);
    })
    .openapi(leave, async (c) => {
      await deps.squads.leave({
        squad: c.req.valid('param').squadId,
        member: caller(c.var.caller.userId),
      });
      return c.body(null, 204);
    })
    .openapi(preview, async (c) => {
      const invite = await deps.squads.previewInvite({
        inviteCode: inviteCodeOf(c.req.valid('param').inviteCode),
        viewer: caller(c.var.caller.userId),
      });
      return c.json({ version: 1 as const, ...invite }, 200);
    })
    .openapi(join, async (c) => {
      const { squad, joined } = await deps.squads.join({
        inviteCode: inviteCodeOf(c.req.valid('param').inviteCode),
        member: caller(c.var.caller.userId),
      });
      return joined ? c.json(wire(squad), 201) : c.json(wire(squad), 200);
    });

  const publicRoutes = new OpenAPIHono().openapi(publicPreview, async (c) => {
    const { name, memberCount, full, members } = await deps.squads.previewPublicInvite(
      inviteCodeOf(c.req.valid('param').inviteCode),
    );
    const squadmates = await deps.members.squadmates(members);
    const looks = members.flatMap((member) => {
      const look = squadmates.get(member)?.character?.look;
      return look === undefined ? [] : [look];
    });
    c.header('cache-control', 'no-store');
    return c.json({ version: 1 as const, name, memberCount, full, looks }, 200);
  });

  return new OpenAPIHono().route('/', signedInRoutes).route('/', publicRoutes);
}
