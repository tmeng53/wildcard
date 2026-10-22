import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInId,
  Emoji,
  MemberId,
  type CheckIns,
  type Reaction as ReactionRecord,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const emoji = Emoji.meta({
  description: 'The reaction: any one emoji, such as ❤️, 💪 or 🇨🇦.',
  example: '❤️',
});

const reactionFields = {
  member: z.uuid().meta({ description: 'Who reacted.' }),
  emoji,
  reactedAt: z.iso.datetime().meta({
    description: 'When they reacted, in UTC with milliseconds.',
    example: '2026-10-18T20:05:00.000Z',
  }),
};

export const ReactionDraft = z
  .strictObject({ version: bodyVersion(1), emoji })
  .openapi('ReactionDraft');
export const Reaction = z
  .strictObject({ version: bodyVersion(1), ...reactionFields })
  .openapi('Reaction');
const ReactionList = z
  .strictObject({ version: bodyVersion(1), reactions: z.array(z.strictObject(reactionFields)) })
  .openapi('ReactionList');

const wire = ({ member, emoji: left, reactedAt }: ReactionRecord) => ({
  member,
  emoji: left,
  reactedAt: reactedAt.toISOString(),
});

const params = z.strictObject({ checkInId: CheckInId });

const failures = {
  401: problem('No bearer token, or not a valid one'),
  404: problem('No check-in with this id that the member can see (`CHECK_IN_NOT_FOUND`)'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * Teammates' reactions on a check-in, like Strava's kudos: one per member, left in the app. `PUT` and `DELETE /check-ins/{checkInId}/reactions/mine`, and
 * `GET /check-ins/{checkInId}/reactions`.
 */
export function reactions(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
}) {
  const react = createRoute({
    method: 'put',
    path: '/check-ins/{checkInId}/reactions/mine',
    operationId: 'reactToCheckIn',
    summary: 'React to a teammate’s check-in',
    description:
      'Leaves the caller’s reaction, in place of any they left before. The same reaction ' +
      'again changes nothing, so it is safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: ReactionDraft } } },
    },
    responses: {
      200: {
        description: 'Already there, or changed from another reaction',
        content: { 'application/json': { schema: Reaction } },
      },
      201: { description: 'Reacted', content: { 'application/json': { schema: Reaction } } },
      400: problem('Not a valid reaction, or the caller’s own check-in (`OWN_CHECK_IN_REACTION`)'),
      ...jsonBodyFailures,
      ...failures,
    },
  });
  const remove = createRoute({
    method: 'delete',
    path: '/check-ins/{checkInId}/reactions/mine',
    operationId: 'removeMyReaction',
    summary: 'Take your reaction off a check-in',
    description: 'Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      204: { description: 'Taken off' },
      400: problem('Not a check-in id'),
      ...failures,
    },
  });
  const list = createRoute({
    method: 'get',
    path: '/check-ins/{checkInId}/reactions',
    operationId: 'listCheckInReactions',
    summary: 'A check-in’s reactions',
    description: 'Oldest first, for its author and the teammates who can see it.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: {
        description: 'The reactions',
        content: { 'application/json': { schema: ReactionList } },
      },
      400: problem('Not a check-in id'),
      ...failures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(react, async (c) => {
      const reacted = await deps.checkIns.react({
        checkIn: c.req.valid('param').checkInId,
        member: MemberId.parse(c.var.caller.userId),
        emoji: c.req.valid('json').emoji,
      });
      const body = { version: 1 as const, ...wire(reacted.reaction) };
      return reacted.outcome === 'created' ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(remove, async (c) => {
      await deps.checkIns.removeReaction({
        checkIn: c.req.valid('param').checkInId,
        member: MemberId.parse(c.var.caller.userId),
      });
      return c.body(null, 204);
    })
    .openapi(list, async (c) => {
      const found = await deps.checkIns.listReactions({
        checkIn: c.req.valid('param').checkInId,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      return c.json({ version: 1 as const, reactions: found.map(wire) }, 200);
    });
}
