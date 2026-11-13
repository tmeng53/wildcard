import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInDraft,
  CheckInEdit,
  CheckInId,
  CheckInKind,
  DEFAULT_PAGE,
  DayRange,
  MyDayRange,
  RecordRange,
  MAX_PAGE,
  decodeCursor,
  encodeCursor,
  LocalDay,
  MemberId,
  SquadId,
  photosOf,
  trainedWithOf,
  storedDisclaimerFields,
  storedMealFields,
  storedTrainingFields,
  type CheckInRecord,
  type CheckIns,
  PhotoSize,
  WorkoutView,
  workoutView,
  type PhotoRef,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { Log } from '../log.js';
import type { PublishEvent } from '../events.js';
import type { PhotoStorage, VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { CommentEntry, wireComment } from './comments.js';
import { ReactionEntry, wireReaction } from './reactions.js';

const checkInFields = {
  version: bodyVersion(1),
  id: z.uuid(),
  member: z.uuid().meta({ description: 'The member who made it.' }),
  day: LocalDay.meta({
    description:
      'The member’s local day it counts for, in their profile’s time zone: `postedDay` or one of the 7 days before it (补打卡).',
  }),
  postedDay: LocalDay.optional().meta({
    description:
      'The member’s local day when they posted it (their day at `createdAt`), which orders the ' +
      'squad’s feed. Before `day` when the check-in was made for an earlier day (补打卡). Always ' +
      'sent; optional only so copies saved before it existed still read.',
  }),
  createdAt: z.iso.datetime().meta({
    description: 'When the member made it, in UTC with milliseconds.',
    example: '2026-10-18T14:03:00.000Z',
  }),
  audience: z.array(z.uuid()).meta({
    description:
      'The squads it went to, in the member’s order. On someone else’s check-in, only the ' +
      'viewer’s own squads are listed.',
  }),
  inFeed: z.boolean().meta({
    description:
      '发布到动态: whether it is a post in its squads’ 动态. One that isn’t still counts for ' +
      'them, but only its author sees it.',
  }),
};

/** How long a photo's view URL works. The app lists again for fresh ones. */
const PHOTO_VIEW_SECONDS = 60 * 60;

/** A photo as the app reads it: its name, a URL to view it and its size. */
export const PhotoView = z
  .strictObject({
    path: z.string().meta({ description: 'The photo’s name, as the check-in was saved with.' }),
    url: z.url().meta({ description: '`GET` the photo here. It works for an hour.' }),
    size: PhotoSize.optional(),
  })
  .openapi('PhotoView');

const photoViews = {
  photos: z
    .array(PhotoView)
    .optional()
    .meta({ description: '1 to 3 photos, the cover first. Missing when there are none.' }),
};
const TrainingView = z
  .strictObject({
    ...storedTrainingFields,
    ...photoViews,
    workout: WorkoutView.optional(),
  })
  .openapi('TrainingView');
const MealView = z.strictObject({ ...storedMealFields, ...photoViews }).openapi('MealView');
const DisclaimerView = z
  .strictObject({ ...storedDisclaimerFields, ...photoViews })
  .openapi('DisclaimerView');

/** A saved check-in, as the app reads it. */
export const CheckIn = z
  .discriminatedUnion('kind', [
    z
      .strictObject({ ...checkInFields, kind: z.literal('trained'), training: TrainingView })
      .openapi('TrainedCheckIn'),
    z
      .strictObject({ ...checkInFields, kind: z.literal('healthyMeal'), meal: MealView })
      .openapi('HealthyMealCheckIn'),
    z
      .strictObject({ ...checkInFields, kind: z.literal('cheatMeal'), meal: MealView })
      .openapi('CheatMealCheckIn'),
    z
      .strictObject({ ...checkInFields, kind: z.literal('disclaimer'), disclaimer: DisclaimerView })
      .openapi('DisclaimerCheckIn'),
  ])
  .openapi('CheckIn');

const CheckInList = z
  .strictObject({ version: bodyVersion(1), checkIns: z.array(CheckIn) })
  .openapi('CheckInList');

/** A check-in with what teammates left on it. */
const postFields = {
  checkIn: CheckIn,
  reactions: z.array(ReactionEntry).meta({ description: 'Teammates’ emoji, oldest first.' }),
  comments: z.array(CommentEntry).meta({
    description:
      'Comments from the author and the teammates the viewer shares a squad with, ' +
      'oldest first. Builds from before comments read the feed without it.',
  }),
};
const SquadPost = z.strictObject(postFields).openapi('SquadPost');

/** A squad's check-ins, each with what teammates left on it. */
const SquadPostList = z
  .strictObject({ version: bodyVersion(1), posts: z.array(SquadPost) })
  .openapi('SquadPostList');

/** A page of the member's own check-ins (历史动态). */
const MyPostPage = z
  .strictObject({
    version: bodyVersion(1),
    posts: z.array(SquadPost).meta({
      description:
        'Newest day first, then newest made. Each shows its whole audience, and the reactions ' +
        'and comments of the member and of members of the squads it went to that the member ' +
        'still shares with them.',
    }),
    next: z
      .string()
      .optional()
      .meta({
        description:
          'Pass as `after` for the next page. Left out on the page that reaches the member’s ' +
          'first check-in.',
      }),
    counts: z
      .strictObject({
        posts: z.int().nonnegative().meta({ description: 'Every check-in the member made.' }),
        reactions: z
          .int()
          .nonnegative()
          .meta({ description: 'The reactions on them the member can see, as on each post.' }),
      })
      .optional()
      .meta({ description: 'On the first page only (no `after`); never narrowed to `kind`.' })
      .openapi('MyPostCounts'),
  })
  .openapi('MyPostPage');

const MyPostQuery = z.strictObject({
  kind: CheckInKind.optional().meta({ description: 'Only check-ins of this kind.' }),
  after: z
    .string()
    .max(200)
    .refine((text) => decodeCursor(text) !== undefined, {
      message: 'Not a `next` this server gave',
    })
    .optional()
    .meta({ description: 'The `next` of the page before; left out for the newest page.' }),
  limit: z.coerce
    .number()
    .int()
    .min(1)
    .max(MAX_PAGE)
    .optional()
    .meta({
      description: `Check-ins on the page: 1 to ${String(MAX_PAGE)}, ${String(DEFAULT_PAGE)} when left out.`,
    }),
});

/** One check-in with what teammates left on it: a post's own page. */
const Post = z.strictObject({ version: bodyVersion(1), ...postFields }).openapi('Post');

const count = (description: string) => z.int().nonnegative().meta({ description });

const Streak = z
  .strictObject({
    days: count('Days in the run.'),
    from: LocalDay.meta({ description: 'Its first day.' }),
    to: LocalDay.meta({ description: 'Its last day.' }),
  })
  .openapi('RecordStreak');

const CurrentStreaks = z
  .strictObject({
    training: Streak.optional(),
    meals: Streak.optional(),
  })
  .meta({
    description:
      'Streaks still going on the member’s clock, the player card’s 外卡: `training`, days ' +
      'trained in a row, a planned rest day or a 请假条 between them neither breaking nor ' +
      'adding; `meals`, days in a row with a meal checked in (健康餐 or 坦白放纵餐), a 请假条 ' +
      'between them neither breaking nor adding. Each ends today, or ' +
      'yesterday while today has none yet, and is left out once broken.',
  })
  .openapi('CurrentStreaks');

/** A member's lifetime counts by kind, wherever the API shows them. */
export const checkInTotalsFields = {
  streaks: CurrentStreaks.optional(),
  trainedDays: count('Days with a 训练; several 训练 on one day count once.'),
  healthyMeals: count('健康餐 check-ins.'),
  cheatMeals: count('坦白放纵餐 check-ins.'),
  disclaimers: count('今日请假条 check-ins taken as leave; a 休息 (`restDay`) is not one.'),
  topSport: z
    .strictObject({
      sport: storedTrainingFields.sport,
      customSport: z
        .string()
        .optional()
        .meta({ description: 'The name of a `custom` sport; a listed sport has none.' }),
      checkIns: count('训练 check-ins of this sport.'),
    })
    .optional()
    .meta({
      description:
        'The sport with the most 训练 (最常练; a custom sport counts by its name), the latest ' +
        'one on a tie. Left out before the first 训练.',
    })
    .openapi('TopSport'),
};

const TrainingRecord = z
  .strictObject({
    version: bodyVersion(1),
    trainings: z
      .array(
        z
          .strictObject({
            id: CheckInId,
            day: LocalDay,
            sport: storedTrainingFields.sport,
            customSport: z
              .string()
              .optional()
              .meta({ description: 'The name of a `custom` sport; a listed sport has none.' }),
            minutes: z
              .int()
              .positive()
              .optional()
              .meta({ description: 'How long it took, when the member said.' }),
          })
          .openapi('TrainingDay'),
      )
      .meta({ description: 'Each 训练 in the range, by day, the earliest made first.' }),
  })
  .openapi('TrainingRecord');

const CheckInTotals = z
  .strictObject({ version: bodyVersion(1), ...checkInTotalsFields })
  .openapi('CheckInTotals');

const customSport = z
  .string()
  .optional()
  .meta({ description: 'The name of a `custom` sport; a listed sport has none.' });

const MateCount = z
  .strictObject({
    memberId: z.uuid(),
    count: count('Shared days, or reactions.'),
  })
  .openapi('RecordMateCount');

const Cheers = z
  .strictObject({
    count: count('Reactions, all time, between the member and their squadmates.'),
    top: MateCount.optional(),
  })
  .meta({ description: 'Reactions and the squadmate with the most (`top`, none at 0).' })
  .openapi('RecordCheers');

const MemberRecords = z
  .strictObject({
    version: bodyVersion(1),
    trainedDays: count('Days with a 训练.'),
    minutes: count('Minutes of every 训练 that says how long it took.'),
    longestMinutes: count('The longest single 训练; left out when none says how long.').optional(),
    // Described on the object: a described reference becomes a wrapper type in generated clients.
    longestStreak: Streak.optional(),
    mealStreak: Streak.optional(),
    currentStreak: Streak.optional(),
    currentMealStreak: Streak.optional(),
    hours: z
      .array(count('训练 started in this hour.'))
      .min(24)
      .max(24)
      .meta({
        description:
          '训练 by the hour of the member’s clock they started at, 0 to 23: the start picked, else ' +
          'the Health workout’s, else the hour posted; a 补打卡 without a start is left out.',
      }),
    weekdays: z
      .array(count('Days trained on this weekday.'))
      .min(7)
      .max(7)
      .meta({ description: 'Days trained by weekday, Monday first.' }),
    sports: z
      .array(
        z
          .strictObject({
            sport: storedTrainingFields.sport,
            customSport,
            days: count('Days the member trained it.'),
          })
          .openapi('RecordSport'),
      )
      .max(3)
      .meta({ description: 'The sports trained on the most days, most first.' }),
    sportCount: count('How many different sports the member trained.'),
    squad: z
      .strictObject({
        id: z.uuid(),
        partner: MateCount.optional(),
        cheersReceived: Cheers,
        cheersGiven: Cheers,
        firsts: z.array(z.string()).meta({
          description:
            'What the member alone is first at in the squad: `latestTrainer`, ' +
            '`earliestTrainer`, `topSport` (their most trained sport) or `mostDays`. Never a ' +
            'tie, never a last place; more may come, so skip an unknown one.',
        }),
      })
      .optional()
      .meta({
        description:
          'How the member stands in their squad, from what squadmates shared with it; left ' +
          'out outside a squad. `partner` is the squadmate who trained on the same days as the ' +
          'member the most.',
      })
      .openapi('SquadRecords'),
  })
  .meta({
    description:
      '外卡记录. `longestStreak`: most days trained in a row, a planned rest day or a 请假条 ' +
      'between them neither breaking nor adding; `mealStreak`: most days in a row with a ' +
      '健康餐, a 请假条 between them neither breaking nor adding; each left ' +
      'out before the first. `currentStreak` and `currentMealStreak`: the same runs still ' +
      'going on the member’s clock (today not counted against them until it is over; a week ' +
      'of rest days in a row breaks training), left out once broken; one is the record when ' +
      'its days reach the longest.',
  })
  .openapi('MemberRecords');

/**
 * Signs a view URL for every photo of these check-ins, in one call to storage. A check-in whose
 * photo file is gone is logged, and `wire` leaves that photo out rather than failing the list.
 */
export async function viewUrls(
  deps: { readonly photos: PhotoStorage; readonly log: Log },
  records: readonly CheckInRecord[],
) {
  const paths = records.flatMap((record) => photosOf(record).map(({ path }) => path));
  const urls = await deps.photos.createViewUrls(paths, PHOTO_VIEW_SECONDS);
  for (const record of records) {
    const missing = photosOf(record).filter(({ path }) => !urls.has(path)).length;
    if (missing > 0) {
      deps.log.warn('A check-in refers to photos that are not in storage.', {
        checkIn: record.id,
        missing,
      });
    }
  }
  return urls;
}

type ViewUrls = Awaited<ReturnType<typeof viewUrls>>;

/** The check-in as the app reads it: each photo with the URL to view it. */
function wire(record: CheckInRecord, urls: ViewUrls) {
  const withUrls = <T extends { readonly photos?: readonly PhotoRef[] | undefined }>({
    photos,
    ...fields
  }: T) => {
    if (photos === undefined) return fields;
    // A photo whose file is gone is left out; a check-in left with none has no `photos`.
    const views = photos.flatMap(({ path, size }) => {
      const url = urls.get(path);
      if (url === undefined) return [];
      return [size === undefined ? { path, url: url.href } : { path, url: url.href, size }];
    });
    return views.length === 0 ? fields : { ...fields, photos: views };
  };
  const base = {
    version: 1 as const,
    id: record.id,
    member: record.member,
    day: record.day,
    postedDay: record.postedDay ?? record.day,
    createdAt: record.createdAt.toISOString(),
    audience: [...record.audience],
    inFeed: record.inFeed,
  };
  switch (record.kind) {
    case 'trained': {
      const { workout, ...training } = record.training;
      return {
        ...base,
        kind: record.kind,
        training: {
          ...withUrls(training),
          ...(workout === undefined ? {} : { workout: workoutView(workout) }),
        },
      };
    }
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...base, kind: record.kind, meal: withUrls(record.meal) };
    case 'disclaimer':
      return { ...base, kind: record.kind, disclaimer: withUrls(record.disclaimer) };
  }
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in or photo storage can’t be reached right now'),
};

/**
 * Daily check-ins: `PUT /check-ins/{id}` saves one, `PATCH` and `DELETE` the same path edit and
 * delete the member's own, and `GET` reads it as a post (its own page), `GET /squads/{squadId}/check-ins` (the squad's feed, with reactions and
 * comments) and `GET /me/check-ins` read them back for a range of days, and
 * `GET /me/check-in-totals` counts all of the member's own, and `GET /me/trainings` lists their
 * 训练 by day for 我's training record.
 */
export function checkIns(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
  readonly photos: PhotoStorage;
  readonly log: Log;
  /** Tells what follows a new check-in (its squads' coaches look at it). */
  readonly publish: PublishEvent;
}) {
  const save = createRoute({
    method: 'put',
    path: '/check-ins/{id}',
    operationId: 'saveCheckIn',
    summary: 'Save a check-in',
    description:
      'The app makes the id, so a save can be retried: the same check-in again answers 200 ' +
      'with the saved one, different contents under a saved id answer 409. Photos are ' +
      'uploaded first, through `POST /photo-uploads`, and listed by path.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ id: CheckInId }),
      body: {
        required: true,
        content: { 'application/json': { schema: CheckInDraft.meta({ id: 'CheckInDraft' }) } },
      },
    },
    responses: {
      200: {
        description: 'Already saved: this was a retry',
        content: { 'application/json': { schema: CheckIn } },
      },
      201: { description: 'Saved', content: { 'application/json': { schema: CheckIn } } },
      400: problem(
        'Not a valid check-in, made more than 48 hours ago or ahead of the server’s clock, ' +
          'counted for the wrong day (after the day it was posted on or more than 7 before it), ' +
          'a 请假条 for a day the member trained on (`ALREADY_TRAINED`), naming someone it was ' +
          'done with who isn’t a squadmate it is shared to, or on one off the 动态 ' +
          '(`TRAINED_WITH_NOT_SQUADMATE`), or ' +
          'with a photo that isn’t uploaded',
      ),
      403: problem('Sent to a squad the member isn’t in, or with someone else’s photo'),
      409: problem(
        'The id holds a different check-in, another check-in uses one of the photos, or the ' +
          'member already posted its workout (`WORKOUT_ALREADY_POSTED`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const edit = createRoute({
    method: 'patch',
    path: '/check-ins/{id}',
    operationId: 'editCheckIn',
    summary: 'Edit one of the member’s own check-ins',
    description:
      'Replaces the kind’s fields and the photos, all of them, as they are to be; the kind, ' +
      'day, time and audience stay as posted. The same edit again changes nothing, so a retry ' +
      'is safe. New photos are uploaded first, through `POST /photo-uploads`; photos the edit ' +
      'leaves out are deleted. Teammates’ reactions and comments stay. A 训练 that leaves ' +
      '`trainedWith` out keeps the squadmates it named; `[]` names none.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ id: CheckInId }),
      body: {
        required: true,
        content: { 'application/json': { schema: CheckInEdit.meta({ id: 'CheckInEdit' }) } },
      },
    },
    responses: {
      200: { description: 'Saved', content: { 'application/json': { schema: CheckIn } } },
      400: problem(
        'Not a valid edit, of another kind than the check-in (`CHECK_IN_KIND_CHANGED`), ' +
          'newly naming someone it was done with who isn’t a squadmate it is shared to ' +
          '(`TRAINED_WITH_NOT_SQUADMATE`), or with a photo that isn’t uploaded',
      ),
      403: problem('A teammate’s check-in (`NOT_YOUR_CHECK_IN`), or someone else’s photo'),
      404: problem('No check-in with this id that the member can see (`CHECK_IN_NOT_FOUND`)'),
      409: problem(
        'Another check-in uses one of the photos, or another of the member’s posts has its workout',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const remove = createRoute({
    method: 'delete',
    path: '/check-ins/{id}',
    operationId: 'deleteCheckIn',
    summary: 'Delete one of the member’s own check-ins',
    description:
      'Deletes it with its photos and the reactions and comments on it. One already gone ' +
      'answers 204 too, so a retry is safe.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ id: CheckInId }) },
    responses: {
      204: { description: 'Deleted, or gone already' },
      400: problem('Not a check-in id'),
      403: problem('A teammate’s check-in (`NOT_YOUR_CHECK_IN`)'),
      404: problem('Another member’s check-in the caller can’t see (`CHECK_IN_NOT_FOUND`)'),
      ...signedInFailures,
    },
  });

  const listForSquad = createRoute({
    method: 'get',
    path: '/squads/{squadId}/check-ins',
    operationId: 'listSquadCheckIns',
    summary: 'A squad’s check-ins for a range of days, with their reactions and comments',
    description:
      'The squad’s feed: check-ins sent to the squad by members still in it and posted on a day ' +
      'in the range (`postedDay`), newest posted first, ' +
      'each with the reactions and comments of the teammates the viewer shares a squad with. ' +
      'Others’ posts only from when the viewer joined the squad. Only for members of the squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }), query: DayRange },
    responses: {
      200: {
        description: 'The check-ins',
        content: { 'application/json': { schema: SquadPostList } },
      },
      400: problem('Not a valid range of days (at most 31)'),
      403: problem('The member isn’t in this squad'),
      ...signedInFailures,
    },
  });

  const findPost = createRoute({
    method: 'get',
    path: '/check-ins/{id}',
    operationId: 'getPost',
    summary: 'One check-in, with its reactions and comments',
    description:
      'A post’s own page, as the feed shows it: for its author, even from a squad they left, ' +
      'or a teammate who shares a squad it went to.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ id: CheckInId }) },
    responses: {
      200: { description: 'The post', content: { 'application/json': { schema: Post } } },
      400: problem('Not a check-in id'),
      404: problem('No check-in with this id that the member can see (`CHECK_IN_NOT_FOUND`)'),
      ...signedInFailures,
    },
  });

  const listMine = createRoute({
    method: 'get',
    path: '/me/check-ins',
    operationId: 'listMyCheckIns',
    summary: 'The signed-in member’s check-ins for a range of days',
    description:
      'Newest day first, each with its whole audience. Posts shared to no squad only with ' +
      '`unshared=include`.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: MyDayRange },
    responses: {
      200: {
        description: 'The check-ins',
        content: { 'application/json': { schema: CheckInList } },
      },
      400: problem('Not a valid range of days (at most 31)'),
      ...signedInFailures,
    },
  });

  const myPosts = createRoute({
    method: 'get',
    path: '/me/posts',
    operationId: 'listMyPosts',
    summary: 'The signed-in member’s own check-ins, a page at a time, with their reactions',
    description:
      '历史动态: everything the member posted, wherever it went, including squads they left. ' +
      'Pages follow from `next`, so posts made meanwhile never shift them.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: MyPostQuery },
    responses: {
      200: {
        description: 'The page',
        content: { 'application/json': { schema: MyPostPage } },
      },
      400: problem('Not a valid kind, limit or `after`'),
      ...signedInFailures,
    },
  });

  const totals = createRoute({
    method: 'get',
    path: '/me/check-in-totals',
    operationId: 'getMyCheckInTotals',
    summary: 'Everything the signed-in member ever checked in, counted by kind',
    description: 'All of their check-ins, wherever they went; 我 shows them. Counts only go up.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The counts',
        content: { 'application/json': { schema: CheckInTotals } },
      },
      ...signedInFailures,
    },
  });

  const memberRecords = createRoute({
    method: 'get',
    path: '/me/records',
    operationId: 'getMyRecords',
    summary: 'The signed-in member’s records (外卡记录)',
    description:
      '外卡记录, opened from 我’s 训练记录: streaks, when and what they train, and how they ' +
      'stand in their squad, worked out from their check-ins and plans on every read.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The records',
        content: { 'application/json': { schema: MemberRecords } },
      },
      ...signedInFailures,
    },
  });

  const trainings = createRoute({
    method: 'get',
    path: '/me/trainings',
    operationId: 'listMyTrainings',
    summary: 'The signed-in member’s 训练 for a range of days, for their training record',
    description:
      '训练记录 on 我: each 训练 the member posted for a day in the range, wherever it went, ' +
      'with its sport and minutes only. At most 371 days at a time.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: RecordRange },
    responses: {
      200: {
        description: 'The record',
        content: { 'application/json': { schema: TrainingRecord } },
      },
      400: problem('Not a valid range of days (at most 371)'),
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(save, async (c) => {
      const { checkIn, created } = await deps.checkIns.save({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
        draft: c.req.valid('json'),
      });
      const body = wire(checkIn, await viewUrls(deps, [checkIn]));
      // The coach answers posts; a check-in only recorded has nothing to answer under.
      if (created && checkIn.inFeed && checkIn.audience.length > 0) {
        await deps.publish({
          version: 1,
          kind: 'check-in.created',
          checkIn: checkIn.id,
          squads: [...checkIn.audience],
        });
        await publishTrainedWith(deps.publish, checkIn);
      }
      return created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(edit, async (c) => {
      const checkIn = await deps.checkIns.edit({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
        edit: c.req.valid('json'),
      });
      // Everyone it names: those told of this post before are not told again.
      await publishTrainedWith(deps.publish, checkIn);
      return c.json(wire(checkIn, await viewUrls(deps, [checkIn])), 200);
    })
    .openapi(remove, async (c) => {
      await deps.checkIns.delete({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
      });
      return c.body(null, 204);
    })
    .openapi(listForSquad, async (c) => {
      const posts = await deps.checkIns.listForSquad({
        viewer: MemberId.parse(c.var.caller.userId),
        squad: c.req.valid('param').squadId,
        days: c.req.valid('query'),
      });
      const urls = await viewUrls(
        deps,
        posts.map(({ checkIn }) => checkIn),
      );
      return c.json(
        {
          version: 1 as const,
          posts: posts.map(({ checkIn, reactions, comments }) => ({
            checkIn: wire(checkIn, urls),
            reactions: reactions.map(wireReaction),
            comments: comments.map(wireComment),
          })),
        },
        200,
      );
    })
    .openapi(findPost, async (c) => {
      const { checkIn, reactions, comments } = await deps.checkIns.post({
        id: c.req.valid('param').id,
        viewer: MemberId.parse(c.var.caller.userId),
      });
      const urls = await viewUrls(deps, [checkIn]);
      return c.json(
        {
          version: 1 as const,
          checkIn: wire(checkIn, urls),
          reactions: reactions.map(wireReaction),
          comments: comments.map(wireComment),
        },
        200,
      );
    })
    .openapi(listMine, async (c) => {
      const { from, to, unshared } = c.req.valid('query');
      const records = await deps.checkIns.listMine({
        member: MemberId.parse(c.var.caller.userId),
        days: { from, to },
        ...(unshared === undefined ? {} : { unshared }),
      });
      const urls = await viewUrls(deps, records);
      return c.json(
        { version: 1 as const, checkIns: records.map((record) => wire(record, urls)) },
        200,
      );
    })
    .openapi(myPosts, async (c) => {
      const { kind, after, limit } = c.req.valid('query');
      const page = await deps.checkIns.listMyPosts({
        member: MemberId.parse(c.var.caller.userId),
        kind,
        after: after === undefined ? undefined : decodeCursor(after),
        limit: limit ?? DEFAULT_PAGE,
      });
      const urls = await viewUrls(
        deps,
        page.posts.map(({ checkIn }) => checkIn),
      );
      return c.json(
        {
          version: 1 as const,
          posts: page.posts.map(({ checkIn, reactions, comments }) => ({
            checkIn: wire(checkIn, urls),
            reactions: reactions.map(wireReaction),
            comments: comments.map(wireComment),
          })),
          ...(page.next === undefined ? {} : { next: encodeCursor(page.next) }),
          ...(page.counts === undefined ? {} : { counts: page.counts }),
        },
        200,
      );
    })
    .openapi(totals, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const [counts, streaks] = await Promise.all([
        deps.checkIns.totals(member),
        deps.checkIns.currentStreaks({ member }),
      ]);
      return c.json({ version: 1 as const, ...counts, streaks }, 200);
    })
    .openapi(memberRecords, async (c) => {
      const found = await deps.checkIns.records(MemberId.parse(c.var.caller.userId));
      const mate = (entry: { readonly member: string; readonly count: number }) => ({
        memberId: entry.member,
        count: entry.count,
      });
      const cheers = (value: {
        readonly count: number;
        readonly top?: { readonly member: string; readonly count: number };
      }) => ({
        count: value.count,
        ...(value.top === undefined ? {} : { top: mate(value.top) }),
      });
      const { squad, ...mine } = found;
      return c.json(
        {
          version: 1 as const,
          ...mine,
          hours: [...mine.hours],
          weekdays: [...mine.weekdays],
          sports: [...mine.sports],
          ...(squad === undefined
            ? {}
            : {
                squad: {
                  id: squad.id,
                  ...(squad.partner === undefined ? {} : { partner: mate(squad.partner) }),
                  cheersReceived: cheers(squad.cheersReceived),
                  cheersGiven: cheers(squad.cheersGiven),
                  firsts: [...squad.firsts],
                },
              }),
        },
        200,
      );
    })
    .openapi(trainings, async (c) => {
      const { from, to } = c.req.valid('query');
      const list = await deps.checkIns.trainings({
        member: MemberId.parse(c.var.caller.userId),
        from,
        to,
      });
      return c.json({ version: 1 as const, trainings: list }, 200);
    });
}

/** Tells the squadmates a 训练 names it was done with (一起练), when it names any. */
async function publishTrainedWith(publish: PublishEvent, checkIn: CheckInRecord): Promise<void> {
  const members = trainedWithOf(checkIn);
  if (members.length === 0) return;
  await publish({
    version: 1,
    kind: 'check-in.trained-with',
    checkIn: checkIn.id,
    author: checkIn.member,
    members: [...members],
  });
}
