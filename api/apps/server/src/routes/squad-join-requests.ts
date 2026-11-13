import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import type { Members } from '@wildcard/members';
import { MemberId as ProfileMember } from '@wildcard/members';
import {
  JoinRequestId,
  MemberId,
  SquadId,
  type JoinRequest as JoinRequestRecord,
  type Squads,
} from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import { tellApproved, type JoinRequestNewsDependencies } from '../flows/join-requests.js';
import type { PublishEvent } from '../events.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { LookBody } from './character.js';

/** A request to join a squad (入队申请), as the member who asked sees it. */
export const JoinRequest = z
  .strictObject({
    version: bodyVersion(1),
    id: z.uuid(),
    squadId: z.uuid(),
    squadName: z.string().meta({ description: 'The squad’s name now.' }),
    note: z.string().optional().meta({ description: 'What the member wrote the captain (备注).' }),
    askedAt: z.iso.datetime().meta({ description: 'When they asked, in UTC.' }),
    status: z.string().meta({
      description:
        '`waiting` for the captain, `approved` (the member is in the squad), `declined`, ' +
        '`withdrawn` by the member (or by asking another squad) or `cancelled` (they got into a ' +
        'squad another way, or the squad ended). More may come: treat another as over.',
    }),
    answeredAt: z.iso.datetime().optional().meta({ description: 'When it ended, in UTC.' }),
    memberCount: z.int().meta({ description: 'How many members the squad has now.' }),
    looks: z.array(LookBody).meta({
      description:
        'The members’ characters, the earliest to join first, as the invite showed them. ' +
        'Members who haven’t made theirs yet are left out. No names or ids.',
    }),
    captain: z
      .strictObject({ nickname: z.string(), look: LookBody })
      .optional()
      .meta({ description: 'The captain who answers it; left out until they made a character.' }),
  })
  .openapi('JoinRequest');

const MyJoinRequest = z
  .strictObject({
    version: bodyVersion(1),
    request: JoinRequest.optional().meta({
      description: 'The member’s newest request to join, waiting or ended; left out if none.',
    }),
  })
  .openapi('MyJoinRequest');

const WaitingJoinRequest = z
  .strictObject({
    id: z.uuid(),
    member: z.uuid().meta({ description: 'Who asked: their Supabase Auth user id.' }),
    nickname: z.string().optional().meta({ description: 'Their nickname, once they made one.' }),
    look: LookBody.optional(),
    note: z.string().optional().meta({ description: 'What they wrote the captain (备注).' }),
    askedAt: z.iso.datetime().meta({ description: 'When they asked, in UTC.' }),
  })
  .openapi('WaitingJoinRequest');

const WaitingJoinRequests = z
  .strictObject({
    version: bodyVersion(1),
    requests: z.array(WaitingJoinRequest).meta({
      description: 'The requests waiting for the captain, the earliest first.',
    }),
  })
  .openapi('WaitingJoinRequests');

const JoinAnswer = z
  .strictObject({
    version: bodyVersion(1),
    approve: z
      .boolean()
      .meta({ description: '`true` lets the member in, `false` turns them away.' }),
  })
  .openapi('JoinAnswer');

const JoinApproval = z
  .strictObject({
    version: bodyVersion(1),
    required: z.boolean().meta({
      description:
        'Whether joining needs the captain’s OK (入队需要审核): on for a squad that never set it.',
    }),
  })
  .openapi('JoinApproval');

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** What a request shows of its squad: as the invite did, and its captain. */
export interface JoinRequestCardDependencies {
  readonly squads: Pick<Squads, 'captainOf' | 'membersOf'>;
  readonly members: Pick<Members, 'squadmates'>;
}

/** A request as the member who asked reads it, with the squad it asks to join. */
export async function wireJoinRequest(
  deps: JoinRequestCardDependencies,
  request: JoinRequestRecord,
): Promise<z.infer<typeof JoinRequest>> {
  const [members, captain] = await Promise.all([
    deps.squads.membersOf(request.squad),
    deps.squads.captainOf(request.squad),
  ]);
  const ids = members.map((member) => ProfileMember.parse(member));
  const profiles = await deps.members.squadmates(
    captain === undefined || members.includes(captain)
      ? ids
      : [...ids, ProfileMember.parse(captain)],
  );
  const characterOf = (member: string) => profiles.get(ProfileMember.parse(member))?.character;
  const captainCharacter = captain === undefined ? undefined : characterOf(captain);
  return {
    version: 1,
    id: request.id,
    squadId: request.squad,
    squadName: request.squadName,
    ...(request.note === undefined ? {} : { note: request.note }),
    askedAt: request.askedAt.toISOString(),
    status: request.answer?.kind ?? 'waiting',
    ...(request.answer === undefined ? {} : { answeredAt: request.answer.at.toISOString() }),
    memberCount: members.length,
    looks: members.flatMap((member) => {
      const look = characterOf(member)?.look;
      return look === undefined ? [] : [look];
    }),
    ...(captainCharacter == null
      ? {}
      : { captain: { nickname: captainCharacter.nickname, look: captainCharacter.look } }),
  };
}

/**
 * 入队申请 (Tracy, 2026-11-12): the switch that makes joining need the captain's OK, the requests
 * waiting for it and the captain's answer, and the member's own request. Asking is opening the
 * invite (`POST /squad-invites/{inviteCode}/accept`).
 */
export function squadJoinRequests(
  deps: JoinRequestNewsDependencies & {
    readonly verifyToken: VerifyToken;
    readonly squads: Squads;
    readonly members: Pick<Members, 'squadmates'>;
    /** Tells what follows a join (the squad's coach welcomes the member) once it is saved. */
    readonly publish: PublishEvent;
  },
) {
  const squadParams = z.strictObject({ squadId: SquadId });
  const answerParams = z.strictObject({ squadId: SquadId, requestId: JoinRequestId });
  const json = <T extends z.ZodType>(description: string, schema: T) => ({
    description,
    content: { 'application/json': { schema } },
  });
  const notInSquad = problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)');
  const notCaptain = problem(
    'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
      '(`NOT_SQUAD_CAPTAIN`)',
  );

  const readApproval = createRoute({
    method: 'get',
    path: '/squads/{squadId}/join-approval',
    operationId: 'getSquadJoinApproval',
    summary: 'Whether joining the squad needs the captain’s OK',
    description: 'For its members.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      200: json('The setting', JoinApproval),
      400: problem('Not a valid squad id'),
      403: notInSquad,
      ...signedInFailures,
    },
  });

  const setApproval = createRoute({
    method: 'put',
    path: '/squads/{squadId}/join-approval',
    operationId: 'setSquadJoinApproval',
    summary: 'Turn the captain’s OK to join on or off',
    description:
      'For the captain. Counts at once for the next invite opened; requests already waiting ' +
      'still wait for an answer. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: JoinApproval } } },
    },
    responses: {
      200: json('The setting, changed', JoinApproval),
      400: problem('Not a valid squad id'),
      403: notCaptain,
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const listWaiting = createRoute({
    method: 'get',
    path: '/squads/{squadId}/join-requests',
    operationId: 'listSquadJoinRequests',
    summary: 'The requests waiting for the captain',
    description: 'For the captain: who asked, their character and note, the earliest first.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      200: json('The waiting requests', WaitingJoinRequests),
      400: problem('Not a valid squad id'),
      403: notCaptain,
      ...signedInFailures,
    },
  });

  const answer = createRoute({
    method: 'put',
    path: '/squads/{squadId}/join-requests/{requestId}',
    operationId: 'answerSquadJoinRequest',
    summary: 'Let a member in, or turn them away',
    description:
      'For the captain. Letting them in joins them to the squad as a join by its captain, and ' +
      'tells them by push. Answering again the same way is a success.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: answerParams,
      body: { required: true, content: { 'application/json': { schema: JoinAnswer } } },
    },
    responses: {
      200: json('The request, answered', JoinRequest),
      400: problem(
        'Not a valid id, or the squad is full (`SQUAD_FULL`), or the member is in a squad ' +
          'already (`SQUAD_LIMIT_REACHED`), or the request was answered another way ' +
          '(`JOIN_REQUEST_ANSWERED`)',
      ),
      403: notCaptain,
      404: problem('No such request to this squad (`JOIN_REQUEST_UNKNOWN`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const readMine = createRoute({
    method: 'get',
    path: '/me/join-request',
    operationId: 'getMyJoinRequest',
    summary: 'The member’s newest request to join a squad',
    description: 'Waiting or ended, for the 等队长同意 page while they are in no squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: { 200: json('The request, if any', MyJoinRequest), ...signedInFailures },
  });

  const withdraw = createRoute({
    method: 'delete',
    path: '/me/join-request',
    operationId: 'withdrawMyJoinRequest',
    summary: 'Withdraw the member’s waiting request',
    description: 'Safe to repeat: with none waiting, nothing changes.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: { 204: { description: 'Withdrawn, or none was waiting' }, ...signedInFailures },
  });

  const caller = (userId: string) => MemberId.parse(userId);

  return new OpenAPIHono<SignedIn>()
    .openapi(readApproval, async (c) => {
      const required = await deps.squads.joinApproval({
        squad: c.req.valid('param').squadId,
        viewer: caller(c.var.caller.userId),
      });
      return c.json({ version: 1 as const, required }, 200);
    })
    .openapi(setApproval, async (c) => {
      const required = await deps.squads.setJoinApproval({
        squad: c.req.valid('param').squadId,
        member: caller(c.var.caller.userId),
        required: c.req.valid('json').required,
      });
      return c.json({ version: 1 as const, required }, 200);
    })
    .openapi(listWaiting, async (c) => {
      const waiting = await deps.squads.waitingJoinRequests({
        squad: c.req.valid('param').squadId,
        viewer: caller(c.var.caller.userId),
      });
      const profiles = await deps.members.squadmates(
        waiting.map(({ member }) => ProfileMember.parse(member)),
      );
      const requests = waiting.map((request) => {
        const character = profiles.get(ProfileMember.parse(request.member))?.character;
        return {
          id: request.id,
          member: request.member,
          ...(character == null ? {} : { nickname: character.nickname, look: character.look }),
          ...(request.note === undefined ? {} : { note: request.note }),
          askedAt: request.askedAt.toISOString(),
        };
      });
      return c.json({ version: 1 as const, requests }, 200);
    })
    .openapi(answer, async (c) => {
      const { squadId, requestId } = c.req.valid('param');
      const { request, changed } = await deps.squads.answerJoinRequest({
        squad: squadId,
        request: requestId,
        member: caller(c.var.caller.userId),
        approve: c.req.valid('json').approve,
      });
      if (changed && request.answer?.kind === 'approved') {
        await deps.publish({
          version: 1,
          kind: 'squad.joined',
          squad: request.squad,
          member: request.member,
        });
        await tellApproved(deps, request);
      }
      return c.json(await wireJoinRequest(deps, request), 200);
    })
    .openapi(readMine, async (c) => {
      const request = await deps.squads.myJoinRequest(caller(c.var.caller.userId));
      return c.json(
        {
          version: 1 as const,
          ...(request === undefined ? {} : { request: await wireJoinRequest(deps, request) }),
        },
        200,
      );
    })
    .openapi(withdraw, async (c) => {
      await deps.squads.withdrawJoinRequest(caller(c.var.caller.userId));
      return c.body(null, 204);
    });
}
