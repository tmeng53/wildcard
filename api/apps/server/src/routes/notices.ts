import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import {
  MemberId,
  NoticeId,
  PAGE_LIMIT,
  type Broadcast,
  type Notice,
  type NoticePage as Page,
  type Notices,
} from '@wildcard/notices';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** Notices on a page when the app doesn't say. */
const DEFAULT_PAGE = 30;

/** The coaches' names now, by coach id, retired ones too. */
export type CoachNames = () => Promise<ReadonlyMap<string, string>>;

const WireNoticeId = z.int().positive();

/** Words in each language the app speaks; the app shows the one picked in the app. */
const LocalizedWords = z
  .strictObject({
    zhHans: z.string(),
    en: z.string(),
    zhHant: z.string(),
  })
  .openapi('LocalizedWords');

export const NoticeEntry = z
  .strictObject({
    id: WireNoticeId.meta({
      description: 'The order notices were told in: a later one is larger.',
    }),
    kind: z.string().meta({
      description:
        'What it is about: `dailyProgress` (the 6pm push), `weeklyAwards` (the week’s 战报 is ' +
        'in), `sceneMoved` (a teammate moved the squad to another scene), `coachReply` (the ' +
        'squad’s coach answered the caller’s check-in), `coachNote` (the squad’s coach left the ' +
        'caller its morning note, 便条), `unlocked` (a store, prop or piece opened), ' +
        '`comment` (a teammate commented on the caller’s check-in or replied to them), ' +
        '`broadcast` (a notice we sent everyone), `goalSuggestion` (the caller’s squad ' +
        'trained over its weekly goal some weeks in a row, so its captain is suggested a higher ' +
        'one) or `planNextWeek` (the Sunday push asking the caller to plan next week). ' +
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
        description:
          'A push’s words as it was put (`dailyProgress`, `weeklyAwards`, `comment`, `planNextWeek`).',
      }),
    weekStart: z.iso
      .date()
      .optional()
      .meta({
        description:
          'The Monday of the week whose 战报 is in (`weeklyAwards`), or of the week to plan ' +
          '(`planNextWeek`).',
      }),
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
    coach: z
      .string()
      .optional()
      .meta({ description: 'The coach who answered (`coachReply`) or wrote (`coachNote`).' }),
    coachName: z
      .string()
      .optional()
      .meta({ description: 'Its name now (`coachReply`, `coachNote`).' }),
    replied: z
      .boolean()
      .optional()
      .meta({ description: 'Whether the coach wrote a line (`coachReply`); else only its emoji.' }),
    emoji: z.string().optional().meta({ description: 'The coach’s emoji (`coachReply`), if any.' }),
    note: WireNoticeId.optional().meta({
      description: 'The morning note’s id (`coachNote`): the same as the coach activity’s.',
    }),
    day: z.iso
      .date()
      .optional()
      .meta({ description: 'The New York day the morning note was written for (`coachNote`).' }),
    text: z.string().optional().meta({ description: 'The morning note’s words (`coachNote`).' }),
    unlockKind: z
      .string()
      .optional()
      .meta({ description: 'What opened (`unlocked`): `store`, `prop` or `piece`. Skip another.' }),
    item: z
      .string()
      .optional()
      .meta({ description: 'The store’s, prop’s or piece’s id (`unlocked`).' }),
    broadcast: z
      .string()
      .optional()
      .meta({
        description:
          'The broadcast’s id (`broadcast`), the same for every member told it. Its `title` is ' +
          'what it says and `body` its muted second line, if any, each as it says them now.',
      }),
    // A component used more than once takes no description of its own here, so the generated
    // clients read it as the component itself: what each says is on the kind.
    weeks: z.int().positive().optional().meta({
      description: 'How many weeks in a row the squad trained over its goal (`goalSuggestion`).',
    }),
    daysPerMember: z
      .int()
      .min(1)
      .max(7)
      .optional()
      .meta({ description: 'The goal suggested, 人均 N 天 (`goalSuggestion`).' }),
    title: LocalizedWords.optional(),
    body: LocalizedWords.optional(),
    action: z
      .strictObject({
        label: LocalizedWords,
        destination: z.string().meta({
          description:
            'Where it opens: `stores` (商店街), `store/<storeId>`, `schedule` (出赛表), `squad` ' +
            '(小队), `feed` (动态), `post/<checkInId>`, `today` or `me`. More may come: show ' +
            'no button for one you don’t know.',
        }),
      })
      .optional()
      .meta({
        description: 'A button that opens a place in the app (`broadcast`), if any: its `label`.',
      }),
    style: z
      .string()
      .optional()
      .meta({
        description:
          'How the app first shows it (`broadcast`): `banner` (the home’s notice banner) or ' +
          '`celebration` (full screen). Show another as `banner`.',
      }),
    icon: z
      .strictObject({
        kind: z.string().meta({ description: '`store`, `prop` or `piece`. Skip another.' }),
        id: z.string().meta({ description: 'Its id in the app’s art.' }),
      })
      .optional()
      .meta({
        description:
          'The picture beside its words (`broadcast`): a store’s sign, a prop or a piece the app ' +
          'draws; left out, or one this build doesn’t draw, shows its own symbol.',
      }),
    gifts: z
      .array(
        z.strictObject({
          kind: z.string().meta({ description: '`store`, `prop` or `piece`. Skip another.' }),
          id: z.string().meta({ description: 'Its id in the app’s art.' }),
        }),
      )
      .optional()
      .meta({
        description:
          'What it gave the caller when they were told (`broadcast`), already among their ' +
          'unlocks; left out when it gave nothing.',
      }),
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
          notices: await noticeEntries(deps, page),
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
  { notices: told, broadcasts }: Pick<Page, 'notices' | 'broadcasts'>,
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
    told.some(({ kind }) => kind === 'coachReply' || kind === 'coachNote')
      ? deps.coachNames()
      : undefined,
  ]);
  const names = {
    member: (id: string) => profiles?.get(ProfileMember.parse(id))?.character?.nickname,
    coach: (id: string) => coaches?.get(id),
    broadcast: (id: Broadcast['id']) => broadcasts.get(id),
  };
  // A broadcast since lost has nothing to say, so it is left out.
  return told.flatMap((notice) => {
    const entry = wireNotice(notice, names);
    return entry === undefined ? [] : [entry];
  });
}

function wireNotice(
  notice: Notice,
  names: {
    readonly member: (id: string) => string | undefined;
    readonly coach: (id: string) => string | undefined;
    readonly broadcast: (id: Broadcast['id']) => Broadcast | undefined;
  },
): z.infer<typeof NoticeEntry> | undefined {
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
    case 'planNextWeek':
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
    case 'coachNote': {
      const { note, coach, day, text } = notice.subject;
      const coachName = names.coach(coach);
      return {
        ...common,
        note,
        coach,
        day,
        text,
        ...(coachName === undefined ? {} : { coachName }),
      };
    }
    case 'unlocked':
      return { ...common, unlockKind: notice.subject.kind, item: notice.subject.item };
    case 'comment':
      return { ...common, alert: notice.subject.alert, checkIn: notice.subject.checkIn };
    case 'goalSuggestion':
      return {
        ...common,
        weeks: notice.subject.weeks,
        daysPerMember: notice.subject.daysPerMember,
      };
    case 'broadcast': {
      const told = names.broadcast(notice.subject.broadcast);
      if (told === undefined) return undefined;
      const { title, body, action, style, icon, gifts } = told.value;
      return {
        ...common,
        broadcast: told.id,
        title,
        ...(body === undefined ? {} : { body }),
        ...(action === undefined ? {} : { action }),
        style,
        ...(icon === undefined ? {} : { icon }),
        ...(gifts.length === 0 ? {} : { gifts }),
      };
    }
  }
}
