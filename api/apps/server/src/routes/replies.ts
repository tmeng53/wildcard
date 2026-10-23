import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInId,
  MemberId,
  ReplyKind,
  type CheckIns,
  type Reply as ReplyRecord,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const kind = ReplyKind.meta({
  description:
    'Which reply: 准了 (`approved`), 抱抱 (`hug`) or 明天一起 (`together`). The app shows each ' +
    'with its own copy.',
});

const replyFields = {
  member: z.uuid().meta({ description: 'Who replied.' }),
  kind,
  repliedAt: z.iso.datetime().meta({
    description: 'When they replied, in UTC with milliseconds.',
    example: '2026-10-18T20:05:00.000Z',
  }),
};

export const ReplyDraft = z.strictObject({ version: bodyVersion(1), kind }).openapi('ReplyDraft');
export const Reply = z.strictObject({ version: bodyVersion(1), ...replyFields }).openapi('Reply');
/** A reply in a list, which carries the version. */
export const ReplyEntry = z.strictObject(replyFields).openapi('ReplyEntry');
const ReplyList = z
  .strictObject({ version: bodyVersion(1), replies: z.array(ReplyEntry) })
  .openapi('ReplyList');

export const wireReply = ({ member, kind, repliedAt }: ReplyRecord) => ({
  member,
  kind,
  repliedAt: repliedAt.toISOString(),
});

const params = z.strictObject({ checkInId: CheckInId });

const failures = {
  401: problem('No bearer token, or not a valid one'),
  404: problem('No check-in with this id that the member can see (`CHECK_IN_NOT_FOUND`)'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * Teammates' replies to a 今日请假条 (准了 and the like), apart from reactions: one per member,
 * left in the app. `PUT` and `DELETE /check-ins/{checkInId}/replies/mine`, and
 * `GET /check-ins/{checkInId}/replies`.
 */
export function replies(deps: { readonly verifyToken: VerifyToken; readonly checkIns: CheckIns }) {
  const reply = createRoute({
    method: 'put',
    path: '/check-ins/{checkInId}/replies/mine',
    operationId: 'replyToDisclaimer',
    summary: 'Reply to a teammate’s 请假条',
    description:
      'Leaves the caller’s reply, in place of any they left before. The same reply again ' +
      'changes nothing, so it is safe to repeat. Only a 请假条 takes replies.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: ReplyDraft } } },
    },
    responses: {
      200: {
        description: 'Already there, or changed from another reply',
        content: { 'application/json': { schema: Reply } },
      },
      201: { description: 'Replied', content: { 'application/json': { schema: Reply } } },
      400: problem(
        'Not a valid reply, not a 请假条 (`NOT_A_DISCLAIMER`), or the caller’s own ' +
          '(`OWN_DISCLAIMER_REPLY`)',
      ),
      ...jsonBodyFailures,
      ...failures,
    },
  });
  const remove = createRoute({
    method: 'delete',
    path: '/check-ins/{checkInId}/replies/mine',
    operationId: 'removeMyReply',
    summary: 'Take your reply off a 请假条',
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
    path: '/check-ins/{checkInId}/replies',
    operationId: 'listDisclaimerReplies',
    summary: 'A 请假条’s replies',
    description:
      'Oldest first, for its author and the teammates who can see it. Empty for any other ' +
      'check-in.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: { description: 'The replies', content: { 'application/json': { schema: ReplyList } } },
      400: problem('Not a check-in id'),
      ...failures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(reply, async (c) => {
      const replied = await deps.checkIns.reply({
        checkIn: c.req.valid('param').checkInId,
        member: MemberId.parse(c.var.caller.userId),
        kind: c.req.valid('json').kind,
      });
      const body = { version: 1 as const, ...wireReply(replied.reply) };
      return replied.outcome === 'created' ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(remove, async (c) => {
      await deps.checkIns.removeReply({
        checkIn: c.req.valid('param').checkInId,
        member: MemberId.parse(c.var.caller.userId),
      });
      return c.body(null, 204);
    })
    .openapi(list, async (c) => {
      const found = await deps.checkIns.listReplies({
        checkIn: c.req.valid('param').checkInId,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      return c.json({ version: 1 as const, replies: found.map(wireReply) }, 200);
    });
}
