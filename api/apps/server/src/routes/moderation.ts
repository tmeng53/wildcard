import { setTimeout as wait } from 'node:timers/promises';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { CheckInId, MemberId as CheckInMember, type CheckIns } from '@wildcard/check-ins';
import { SquadId as CoachSquadId, type CoachActivity } from '@wildcard/coach';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import {
  BlockedMemberMissingError,
  MemberId,
  ReportId,
  ReportKind,
  ReportedItemMissingError,
  type Moderation,
  type ReportSnapshot,
} from '@wildcard/moderation';

import { bodyVersion } from '../body-version.js';
import { fileReport, type ReportIssueDependencies } from '../flows/report-issues.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { LookBody } from './character.js';

/** How long the answer waits for the issue; a slower one carries on, and the jobs catch up. */
const FILE_WAIT_MS = 5000;

/** A member the signed-in member blocked (已拉黑), as 设置 lists them. */
export const BlockedMember = z
  .strictObject({
    member: z.uuid().meta({ description: 'Who is blocked.' }),
    nickname: z.string().optional().meta({ description: 'Their nickname; left out without one.' }),
    look: LookBody.optional(),
    since: z.iso.datetime().meta({ description: 'When they were blocked, in UTC.' }),
  })
  .openapi('BlockedMember');

export const BlockedMemberList = z
  .strictObject({
    version: bodyVersion(1),
    blocked: z.array(BlockedMember).meta({ description: 'Newest blocked first.' }),
  })
  .openapi('BlockedMemberList');

export const ReportDraft = z
  .strictObject({
    version: bodyVersion(1),
    id: z.uuid().meta({ description: 'Made by the app, so sending again reports once.' }),
    kind: ReportKind.meta({
      description:
        'A teammate’s post (`checkIn`), a comment under one (`comment`), or the coach’s reply ' +
        '(`coachReply`) or answer (`coachAnswer`) there.',
    }),
    checkIn: z.uuid().meta({ description: 'The post, or the post it is under.' }),
    item: z
      .string()
      .min(1)
      .max(100)
      .optional()
      .meta({
        description:
          'For `comment`, the comment’s id; for `coachReply`, the coach’s id; for `coachAnswer`, ' +
          'the id of the member’s comment it answers. Left out for `checkIn`.',
      }),
    squad: z.uuid().optional().meta({
      description: 'For a coach’s line, the squad whose coach said it. Left out otherwise.',
    }),
  })
  .openapi('ReportDraft');

export const ReportSent = z
  .strictObject({ version: bodyVersion(1), id: z.uuid() })
  .openapi('ReportSent');

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

const memberParam = z.strictObject({ memberId: z.uuid() });

/**
 * Blocking a teammate (拉黑) and reporting what was posted (举报), as App Review guideline 1.2
 * asks. A block is two-way and keeps both in the squad: neither sees the other's posts,
 * comments or reactions, nor hears of them. A report hides the thing from the reporter at once
 * and is filed as an issue in our private feedback repository for an admin to look at.
 */
export function moderation(
  deps: {
    readonly verifyToken: VerifyToken;
    readonly moderation: Moderation;
    readonly members: Pick<Members, 'squadmates'>;
    readonly checkIns: Pick<CheckIns, 'post'>;
    readonly coachActivity: Pick<CoachActivity, 'squad'>;
  } & Omit<ReportIssueDependencies, 'moderation'>,
) {
  const list = createRoute({
    method: 'get',
    path: '/me/blocks',
    operationId: 'listMyBlocks',
    summary: 'The members the signed-in member blocked (已拉黑)',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'Who they blocked',
        content: { 'application/json': { schema: BlockedMemberList } },
      },
      ...signedInFailures,
    },
  });

  const block = createRoute({
    method: 'put',
    path: '/me/blocks/{memberId}',
    operationId: 'blockMember',
    summary: 'Block a member (拉黑)',
    description:
      'Two-way: neither sees the other’s posts, comments or reactions, nor is pushed about ' +
      'them. Both stay in their squads. The blocked member isn’t told. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: memberParam },
    responses: {
      204: { description: 'Blocked' },
      400: problem('Not a member id, or the member’s own (`BLOCK_SELF`)'),
      404: problem('No such member (`MEMBER_NOT_FOUND`)'),
      ...signedInFailures,
    },
  });

  const unblock = createRoute({
    method: 'delete',
    path: '/me/blocks/{memberId}',
    operationId: 'unblockMember',
    summary: 'Unblock a member (解除拉黑)',
    description: 'One not blocked answers 204 too, so a retry is safe.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: memberParam },
    responses: {
      204: { description: 'Unblocked, or not blocked' },
      400: problem('Not a member id'),
      ...signedInFailures,
    },
  });

  const report = createRoute({
    method: 'post',
    path: '/reports',
    operationId: 'report',
    summary: 'Report a post, a comment or a coach’s line (举报)',
    description:
      'Hides it from the reporter at once (a post leaves their feed, a comment or line its ' +
      'post) and files it for an admin to look at within 24 hours. Reporting the same thing ' +
      'again keeps the first report.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: ReportDraft } } },
    },
    responses: {
      201: { description: 'Reported', content: { 'application/json': { schema: ReportSent } } },
      200: {
        description: 'Reported before',
        content: { 'application/json': { schema: ReportSent } },
      },
      400: problem('Not a valid report'),
      404: problem(
        'Nothing like it the member can see (`CHECK_IN_NOT_FOUND`, `REPORTED_ITEM_NOT_FOUND`)',
      ),
      409: problem('Another member’s report has this id (`REPORT_ID_TAKEN`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  /** What the reporter saw of the thing they report, and who wrote it; throws when they can't see it. */
  async function lookUp(
    viewer: string,
    draft: z.infer<typeof ReportDraft>,
  ): Promise<{ readonly author?: MemberId; readonly snapshot: ReportSnapshot }> {
    const missing = () => new ReportedItemMissingError(`${draft.kind} ${draft.item ?? ''}`.trim());
    // Throws `CheckInNotFoundError` for a post they can't see.
    const post = await deps.checkIns.post({
      id: CheckInId.parse(draft.checkIn),
      viewer: CheckInMember.parse(viewer),
    });
    if (draft.kind === 'checkIn') {
      const { checkIn } = post;
      const words =
        checkIn.kind === 'trained'
          ? checkIn.training.caption
          : checkIn.kind === 'disclaimer'
            ? checkIn.disclaimer.text
            : checkIn.meal.caption;
      const photos =
        checkIn.kind === 'trained'
          ? checkIn.training.photos
          : checkIn.kind === 'disclaimer'
            ? checkIn.disclaimer.photos
            : checkIn.meal.photos;
      return {
        author: MemberId.parse(checkIn.member),
        snapshot: { ...(words === undefined ? {} : { words }), photos: photos?.length ?? 0 },
      };
    }
    if (draft.item === undefined) throw missing();
    if (draft.kind === 'comment') {
      const comment = post.comments.find((each) => each.id === draft.item);
      if (comment === undefined) throw missing();
      return { author: MemberId.parse(comment.member), snapshot: { words: comment.text } };
    }
    // A coach's line: only in a squad the post went to and the reporter sees it through.
    if (draft.squad === undefined || !post.checkIn.audience.some((each) => each === draft.squad)) {
      throw missing();
    }
    const activity = await deps.coachActivity.squad({
      squad: CoachSquadId.parse(draft.squad),
      checkIns: [draft.checkIn],
    });
    const words =
      draft.kind === 'coachReply'
        ? activity.replies.find((reply) => reply.coach.id === draft.item)?.text
        : activity.answers.find((answer) => answer.comment === draft.item)?.text;
    const said =
      draft.kind === 'coachReply'
        ? activity.replies.some((reply) => reply.coach.id === draft.item)
        : words !== undefined;
    if (!said) throw missing();
    return { snapshot: words === undefined ? {} : { words } };
  }

  return new OpenAPIHono<SignedIn>()
    .openapi(list, async (c) => {
      const blocked = await deps.moderation.blocked(MemberId.parse(c.var.caller.userId));
      const profiles = await deps.members.squadmates(
        blocked.map(({ member }) => ProfileMember.parse(member)),
      );
      return c.json(
        {
          version: 1 as const,
          blocked: blocked.map(({ member, since }) => {
            const character = profiles.get(ProfileMember.parse(member))?.character;
            return {
              member,
              ...(character == null ? {} : { nickname: character.nickname, look: character.look }),
              since: since.toISOString(),
            };
          }),
        },
        200,
      );
    })
    .openapi(block, async (c) => {
      const { memberId } = c.req.valid('param');
      const profiles = await deps.members.squadmates([ProfileMember.parse(memberId)]);
      if (!profiles.has(ProfileMember.parse(memberId)))
        throw new BlockedMemberMissingError(memberId);
      await deps.moderation.block({
        member: MemberId.parse(c.var.caller.userId),
        other: MemberId.parse(memberId),
      });
      return c.body(null, 204);
    })
    .openapi(unblock, async (c) => {
      await deps.moderation.unblock({
        member: MemberId.parse(c.var.caller.userId),
        other: MemberId.parse(c.req.valid('param').memberId),
      });
      return c.body(null, 204);
    })
    .openapi(report, async (c) => {
      const draft = c.req.valid('json');
      const member = c.var.caller.userId;
      const { author, snapshot } = await lookUp(member, draft);
      const { report: saved, fresh } = await deps.moderation.report({
        id: ReportId.parse(draft.id),
        member: MemberId.parse(member),
        kind: draft.kind,
        checkIn: draft.checkIn,
        ...(draft.kind === 'checkIn' ? {} : { item: draft.item }),
        ...(author === undefined ? {} : { author }),
        snapshot,
      });
      if (fresh) {
        const stop = new AbortController();
        const late = wait(FILE_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(
          () => undefined,
        );
        await Promise.race([fileReport({ ...deps, moderation: deps.moderation }, saved), late]);
        stop.abort();
      }
      const body = { version: 1 as const, id: saved.id };
      return fresh ? c.json(body, 201) : c.json(body, 200);
    });
}
