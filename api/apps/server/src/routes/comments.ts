import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInId,
  CommentId,
  CommentText,
  MemberId,
  type CheckIns,
  type Comment as CommentRecord,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const replyTo = MemberId.meta({
  description:
    'Whom the comment replies to (回复 Mia：…): the check-in’s author, or a teammate who can see it.',
});

const commentFields = {
  id: CommentId.meta({ description: 'The comment’s id, which the app picks.' }),
  member: z.uuid().meta({ description: 'Who wrote it.' }),
  text: CommentText,
  replyTo: z.uuid().optional().meta({
    description: 'Whom it replies to, when it does. Gone once their account is deleted.',
  }),
  commentedAt: z.iso.datetime().meta({
    description: 'When it was written, in UTC with milliseconds.',
    example: '2026-10-18T20:05:00.000Z',
  }),
};

export const CommentDraft = z
  .strictObject({ version: bodyVersion(1), text: CommentText, replyTo: replyTo.optional() })
  .openapi('CommentDraft');
export const Comment = z
  .strictObject({ version: bodyVersion(1), ...commentFields })
  .openapi('Comment');
/** A comment in a list, which carries the version. */
export const CommentEntry = z.strictObject(commentFields).openapi('CommentEntry');
const CommentList = z
  .strictObject({ version: bodyVersion(1), comments: z.array(CommentEntry) })
  .openapi('CommentList');

export const wireComment = ({ id, member, text, replyTo: to, commentedAt }: CommentRecord) => ({
  id,
  member,
  text,
  ...(to === undefined ? {} : { replyTo: to }),
  commentedAt: commentedAt.toISOString(),
});

const listParams = z.strictObject({ checkInId: CheckInId });
const params = z.strictObject({ checkInId: CheckInId, commentId: CommentId });

const failures = {
  401: problem('No bearer token, or not a valid one'),
  404: problem('No check-in with this id that the member can see (`CHECK_IN_NOT_FOUND`)'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * Comments on a check-in (动态评论): its author and the teammates who can see it write them,
 * one level deep. `PUT` and `DELETE /check-ins/{checkInId}/comments/{commentId}`, and
 * `GET /check-ins/{checkInId}/comments`.
 */
export function comments(deps: { readonly verifyToken: VerifyToken; readonly checkIns: CheckIns }) {
  const write = createRoute({
    method: 'put',
    path: '/check-ins/{checkInId}/comments/{commentId}',
    operationId: 'commentOnCheckIn',
    summary: 'Comment on a check-in',
    description:
      'Writes the caller’s comment under a check-in they can see, their own included. Comments ' +
      'are never edited; the same comment under the same id again changes nothing, so it is ' +
      'safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: CommentDraft } } },
    },
    responses: {
      200: {
        description: 'Already written',
        content: { 'application/json': { schema: Comment } },
      },
      201: { description: 'Written', content: { 'application/json': { schema: Comment } } },
      400: problem(
        'Not a valid comment, or a reply to someone who can’t see the check-in ' +
          '(`REPLY_TO_NOT_IN_SQUAD`)',
      ),
      409: problem('The id holds a different comment (`COMMENT_ID_CONFLICT`)'),
      ...jsonBodyFailures,
      ...failures,
    },
  });
  const remove = createRoute({
    method: 'delete',
    path: '/check-ins/{checkInId}/comments/{commentId}',
    operationId: 'deleteComment',
    summary: 'Delete your comment',
    description:
      'It is gone for everyone, and works even after you left the squad. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      204: { description: 'Deleted, or already gone' },
      400: problem('Not a check-in or comment id'),
      403: problem('Someone else’s comment (`NOT_YOUR_COMMENT`)'),
      ...failures,
    },
  });
  const list = createRoute({
    method: 'get',
    path: '/check-ins/{checkInId}/comments',
    operationId: 'listCheckInComments',
    summary: 'A check-in’s comments',
    description: 'Oldest first, for its author and the teammates who can see it.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: listParams },
    responses: {
      200: {
        description: 'The comments',
        content: { 'application/json': { schema: CommentList } },
      },
      400: problem('Not a check-in id'),
      ...failures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(write, async (c) => {
      const { checkInId, commentId } = c.req.valid('param');
      const draft = c.req.valid('json');
      const written = await deps.checkIns.comment({
        checkIn: checkInId,
        id: commentId,
        member: MemberId.parse(c.var.caller.userId),
        text: draft.text,
        replyTo: draft.replyTo,
      });
      const body = { version: 1 as const, ...wireComment(written.comment) };
      return written.created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(remove, async (c) => {
      const { checkInId, commentId } = c.req.valid('param');
      await deps.checkIns.deleteComment({
        checkIn: checkInId,
        id: commentId,
        member: MemberId.parse(c.var.caller.userId),
      });
      return c.body(null, 204);
    })
    .openapi(list, async (c) => {
      const found = await deps.checkIns.listComments({
        checkIn: c.req.valid('param').checkInId,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      return c.json({ version: 1 as const, comments: found.map(wireComment) }, 200);
    });
}
