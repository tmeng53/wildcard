import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { cors } from 'hono/cors';
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
    captain: z
      .uuid()
      .nullable()
      .meta({
        description:
          'The captain (队长), who renames the squad, removes members and hands the captaincy on: ' +
          'the creator at first; when the captain leaves, the earliest member to join. Null only ' +
          'once everyone has left.',
      }),
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

const SquadNameBody = z
  .strictObject({ version: bodyVersion(1), name: SquadName })
  .openapi('SquadNameChange');

const SquadCaptainBody = z
  .strictObject({
    version: bodyVersion(1),
    member: z.uuid().meta({ description: 'The member to hand the captaincy to.' }),
  })
  .openapi('SquadCaptainChange');

const SquadInvite = z
  .strictObject({
    version: bodyVersion(1),
    name: z.string().meta({ description: 'The squad’s name.' }),
    memberCount: z.int().meta({ description: 'How many members it has now.' }),
    full: z.boolean().meta({
      description: `True when it has ${String(SQUAD_MEMBER_LIMIT)} members and can’t take more.`,
    }),
    joined: z.boolean().meta({ description: 'True when the caller is in it already.' }),
    looks: z.array(LookBody).meta({
      description:
        'The members’ characters, the earliest to join first, for the join screen to show the ' +
        'squad. Members who haven’t made theirs yet are left out. No names or ids.',
    }),
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
    captain: squad.captain,
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

/** The website, whose invite page (wildcardsquad.com/join/…) looks a code up from the browser. */
const SITE_ORIGINS = ['https://wildcardsquad.com', 'https://www.wildcardsquad.com'];

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
 * Squads: create one with a name, preview and join one by invite code, list mine, read one,
 * leave, and the captain's settings (rename, remove a member, hand on the captaincy). No route
 * deletes a squad: its members leave, and it goes only with its last member's account.
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

  const captainOnly = problem(
    'The caller isn’t the squad’s captain (`NOT_SQUAD_CAPTAIN`), or isn’t in it (`SQUAD_NOT_JOINED`)',
  );

  const rename = createRoute({
    method: 'put',
    path: '/squads/{squadId}/name',
    operationId: 'renameSquad',
    summary: 'Rename a squad',
    description: 'Only its captain. The same name again changes nothing.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: SquadNameBody } } },
    },
    responses: {
      200: squadResponse('The squad, renamed'),
      400: problem('Not a valid squad id or name'),
      403: captainOnly,
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const handCaptaincy = createRoute({
    method: 'put',
    path: '/squads/{squadId}/captain',
    operationId: 'handSquadCaptaincy',
    summary: 'Hand the captaincy to another member',
    description: 'Only the captain. Naming the captain again changes nothing.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: SquadCaptainBody } } },
    },
    responses: {
      200: squadResponse('The squad, with its new captain'),
      400: problem('Not a valid squad id or member id'),
      403: captainOnly,
      404: problem('The member isn’t in the squad (`SQUAD_MEMBER_UNKNOWN`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const removeMember = createRoute({
    method: 'delete',
    path: '/squads/{squadId}/members/{memberId}',
    operationId: 'removeSquadMember',
    summary: 'Leave a squad, or remove a member from it',
    description:
      'Anyone may take themselves out (leaving); only the captain may take out someone else. ' +
      'A captain who leaves hands the captaincy to the earliest member left. Their check-ins ' +
      'leave the squad’s list with them. Safe to repeat: someone not in the squad changes nothing.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId, memberId: MemberId }) },
    responses: {
      204: { description: 'Not in the squad any more' },
      400: problem('Not a valid squad id or member id'),
      403: captainOnly,
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
      // First, so a refusal (404, 429) reaches the page too; a plain GET needs no preflight.
      cors({ origin: SITE_ORIGINS, allowMethods: ['GET'], exposeHeaders: ['Retry-After'] }),
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

  /** The members' characters, in the order given, leaving out anyone without one yet. */
  const looksOf = async (members: readonly MemberId[]) => {
    const squadmates = await deps.members.squadmates(members);
    return members.flatMap((member) => {
      const look = squadmates.get(member)?.character?.look;
      return look === undefined ? [] : [look];
    });
  };

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
    .openapi(rename, async (c) => {
      const squad = await deps.squads.rename({
        squad: c.req.valid('param').squadId,
        member: caller(c.var.caller.userId),
        name: c.req.valid('json').name,
      });
      return c.json(wire(squad), 200);
    })
    .openapi(handCaptaincy, async (c) => {
      const squad = await deps.squads.handCaptaincy({
        squad: c.req.valid('param').squadId,
        member: caller(c.var.caller.userId),
        to: MemberId.parse(c.req.valid('json').member),
      });
      return c.json(wire(squad), 200);
    })
    .openapi(removeMember, async (c) => {
      const { squadId, memberId } = c.req.valid('param');
      await deps.squads.removeMember({
        squad: squadId,
        member: caller(c.var.caller.userId),
        removed: memberId,
      });
      return c.body(null, 204);
    })
    .openapi(preview, async (c) => {
      const { name, memberCount, full, joined, members } = await deps.squads.previewInvite({
        inviteCode: inviteCodeOf(c.req.valid('param').inviteCode),
        viewer: caller(c.var.caller.userId),
      });
      const looks = await looksOf(members);
      return c.json({ version: 1 as const, name, memberCount, full, joined, looks }, 200);
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
    const looks = await looksOf(members);
    c.header('cache-control', 'no-store');
    return c.json({ version: 1 as const, name, memberCount, full, looks }, 200);
  });

  return new OpenAPIHono().route('/', signedInRoutes).route('/', publicRoutes);
}
