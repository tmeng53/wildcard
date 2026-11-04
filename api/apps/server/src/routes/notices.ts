import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId, NoticeId, PAGE_LIMIT, type Notice, type Notices } from '@wildcard/notices';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** Notices on a page when the app doesn't say. */
const DEFAULT_PAGE = 30;

/** The coaches' names now, by coach id, retired ones too. */
export type CoachNames = () => Promise<ReadonlyMap<string, string>>;

const WireNoticeId = z.int().positive();

export const NoticeEntry = z
  .strictObject({
    id: WireNoticeId.meta({
      description: 'The order notices were told in: a later one is larger.',
    }),
    kind: z.string().meta({
      description:
        'What it is about: `dailyProgress` (the 6pm push), `weeklyAwards` (the week’s 战报 is ' +
        'in), `sceneMoved` (a teammate moved the squad to another scene), `coachReply` (the ' +
        'squad’s coach answered the caller’s check-in), `unlocked` (a store or prop opened) or ' +
        '`comment` (a teammate commented on the caller’s check-in or replied to them). ' +
        'More kinds may come: skip one you don’t know.',
    }),
    at: z.iso.datetime().meta({ description: 'When it was told, in UTC.' }),
    squadId: z.uuid().optional().meta({ description: 'The squad it is about, if any.' }),
    alert: z
      .strictObject({
        key: z.string().meta({ description: 'The String Catalog key the push used.' }),
        args: z.array(z.string()).meta({ description: 'Its placeholders’ values, in order.' }),
      })
      .optional()
      .meta({
        description: 'A push’s words as it was put (`dailyProgress`, `weeklyAwards`, `comment`).',
      }),
    weekStart: z.iso
      .date()
      .optional()
      .meta({ description: 'The Monday of the week whose 战报 is in (`weeklyAwards`).' }),
    scene: z.string().optional().meta({ description: 'The scene moved to (`sceneMoved`).' }),
    by: z.uuid().optional().meta({
      description: 'Who moved it (`sceneMoved`); left out once they deleted their account.',
    }),
    byName: z
      .string()
      .optional()
      .meta({ description: 'Their nickname now (`sceneMoved`), when they have one.' }),
    checkIn: z
      .uuid()
      .optional()
      .meta({
        description:
          'The caller’s check-in the coach answered (`coachReply`), or the check-in commented ' +
          'on (`comment`).',
      }),
    coach: z.string().optional().meta({ description: 'The coach who answered (`coachReply`).' }),
    coachName: z.string().optional().meta({ description: 'Its name now (`coachReply`).' }),
    replied: z
      .boolean()
      .optional()
      .meta({ description: 'Whether the coach wrote a line (`coachReply`); else only its emoji.' }),
    emoji: z.string().optional().meta({ description: 'The coach’s emoji (`coachReply`), if any.' }),
    unlockKind: z
      .string()
      .optional()
      .meta({ description: 'What opened (`unlocked`): `store` or `prop`. Skip another.' }),
    item: z.string().optional().meta({ description: 'The store’s or prop’s id (`unlocked`).' }),
  })
  .openapi('NoticeEntry');

export const NoticePage = z
  .strictObject({
    version: bodyVersion(1),
    notices: z.array(NoticeEntry).meta({ description: 'Newest first.' }),
    seenThrough: WireNoticeId.optional().meta({
      description:
        'The newest notice the caller has seen: every one up to it is read. Left out before ' +
        'they first opened 通知.',
    }),
    next: WireNoticeId.optional().meta({
      description: 'Pass as `before` for the next, older page; left out on the last.',
    }),
  })
  .openapi('NoticePage');

export const NoticesSeen = z
  .strictObject({
    version: bodyVersion(1),
    through: WireNoticeId.meta({
      description: 'The newest notice the caller saw, usually the first on the newest page.',
    }),
  })
  .openapi('NoticesSeen');

const NoticeQuery = z.strictObject({
  before: z.coerce
    .number()
    .int()
    .positive()
    .optional()
    .meta({ description: 'The `next` of the page before; left out for the newest page.' }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(PAGE_LIMIT)
    .optional()
    .meta({
      description: `Notices on the page: 1 to ${String(PAGE_LIMIT)}, ${String(DEFAULT_PAGE)} when left out.`,
    }),
});

/**
 * The bell on 动态 (通知): every push and in-app notice the caller was told, kept forever, and how
 * far they have read them.
 */
export function notices(deps: {
  readonly verifyToken: VerifyToken;
  readonly notices: Notices;
  readonly members: Members;
  readonly coachNames: CoachNames;
}) {
  const list = createRoute({
    method: 'get',
    path: '/me/notices',
    operationId: 'listMyNotices',
    summary: 'The caller’s notices (通知)',
    description:
      'Newest first, a page at a time, with how far the caller has read: a notice newer than ' +
      '`seenThrough` is unread, and the bell shows its dot while one is. Names are as they are now.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: NoticeQuery },
    responses: {
      200: {
        description: 'A page of notices',
        content: { 'application/json': { schema: NoticePage } },
      },
      400: problem('Not a valid `before` or `limit`'),
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  const seen = createRoute({
    method: 'put',
    path: '/me/notices/seen',
    operationId: 'markMyNoticesSeen',
    summary: 'Mark the caller’s notices read (通知)',
    description:
      'Opening 通知 marks every notice up to the newest read. Never goes back: an older one, or ' +
      'the same again, changes nothing, so it is safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: NoticesSeen } } },
    },
    responses: {
      200: {
        description: 'Read up to there',
        content: { 'application/json': { schema: NoticesSeen } },
      },
      400: problem('Not a valid body'),
      401: problem('No bearer token, or not a valid one'),
      404: problem('Not one of the caller’s notices (`NOTICE_NOT_FOUND`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(list, async (c) => {
      const { before, limit } = c.req.valid('query');
      const page = await deps.notices.page({
        member: MemberId.parse(c.var.caller.userId),
        ...(before === undefined ? {} : { before: NoticeId.parse(before) }),
        limit: limit ?? DEFAULT_PAGE,
      });
      return c.json(
        {
          version: 1 as const,
          notices: await noticeEntries(deps, page.notices),
          ...(page.seenThrough === undefined ? {} : { seenThrough: page.seenThrough }),
          ...(page.next === undefined ? {} : { next: page.next }),
        },
        200,
      );
    })
    .openapi(seen, async (c) => {
      const { through } = c.req.valid('json');
      await deps.notices.markSeen(MemberId.parse(c.var.caller.userId), NoticeId.parse(through));
      return c.json({ version: 1 as const, through }, 200);
    });
}

/** The notices as the app reads them, with the names they show as they are now. */
export async function noticeEntries(
  deps: { readonly members: Members; readonly coachNames: CoachNames },
  told: readonly Notice[],
): Promise<z.infer<typeof NoticeEntry>[]> {
  const movers = [
    ...new Set(
      told.flatMap((notice) =>
        notice.kind === 'sceneMoved' && notice.subject.by !== null ? [notice.subject.by] : [],
      ),
    ),
  ];
  const [profiles, coaches] = await Promise.all([
    movers.length === 0
      ? undefined
      : deps.members.squadmates(movers.map((each) => ProfileMember.parse(each))),
    told.some(({ kind }) => kind === 'coachReply') ? deps.coachNames() : undefined,
  ]);
  const names = {
    member: (id: string) => profiles?.get(ProfileMember.parse(id))?.character?.nickname,
    coach: (id: string) => coaches?.get(id),
  };
  return told.map((notice) => wireNotice(notice, names));
}

function wireNotice(
  notice: Notice,
  names: {
    readonly member: (id: string) => string | undefined;
    readonly coach: (id: string) => string | undefined;
  },
): z.infer<typeof NoticeEntry> {
  const common = {
    id: notice.id,
    kind: notice.kind,
    at: notice.at.toISOString(),
    ...(notice.squad === undefined ? {} : { squadId: notice.squad }),
  };
  switch (notice.kind) {
    case 'dailyProgress':
      return { ...common, alert: notice.subject.alert };
    case 'weeklyAwards':
      return { ...common, alert: notice.subject.alert, weekStart: notice.subject.weekStart };
    case 'sceneMoved': {
      const { scene, by } = notice.subject;
      const byName = by === null ? undefined : names.member(by);
      return {
        ...common,
        scene,
        ...(by === null ? {} : { by }),
        ...(byName === undefined ? {} : { byName }),
      };
    }
    case 'coachReply': {
      const { checkIn, coach, replied, emoji } = notice.subject;
      const coachName = names.coach(coach);
      return {
        ...common,
        checkIn,
        coach,
        replied,
        ...(coachName === undefined ? {} : { coachName }),
        ...(emoji === null ? {} : { emoji }),
      };
    }
    case 'unlocked':
      return { ...common, unlockKind: notice.subject.kind, item: notice.subject.item };
    case 'comment':
      return { ...common, alert: notice.subject.alert, checkIn: notice.subject.checkIn };
  }
}
