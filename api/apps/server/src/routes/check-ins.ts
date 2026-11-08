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
import { coachLooksAtCheckIn, type CoachLooker } from '../flows/coach-answer.js';
import type { Log } from '../log.js';
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
};

/** How long a photo's view URL works. The app lists again for fresh ones. */
const PHOTO_VIEW_SECONDS = 60 * 60;

const photoViews = {
  photos: z
    .array(
      z
        .strictObject({
          path: z
            .string()
            .meta({ description: 'The photo’s name, as the check-in was saved with.' }),
          url: z.url().meta({ description: '`GET` the photo here. It works for an hour.' }),
          size: PhotoSize.optional(),
        })
        .openapi('PhotoView'),
    )
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

/**
 * Installed builds from before the replies were removed (#180) still require `replies` on each
 * post and fail to read the whole feed without it, so every post keeps an empty one. It stays out
 * of the contract: newer builds ignore keys they don't know. Remove it once no installed build
 * predates #180.
 */
const installedBuildsReplies: { readonly replies: readonly never[] } = { replies: [] };

const count = (description: string) => z.int().nonnegative().meta({ description });

/** A member's lifetime counts by kind, wherever the API shows them. */
export const checkInTotalsFields = {
  trainedDays: count('Days with a 练了; several 练了 on one day count once.'),
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
      checkIns: count('练了 check-ins of this sport.'),
    })
    .optional()
    .meta({
      description:
        'The sport with the most 练了 (最常练; a custom sport counts by its name), the latest ' +
        'one on a tie. Left out before the first 练了.',
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
      .meta({ description: 'Each 练了 in the range, by day, the earliest made first.' }),
  })
  .openapi('TrainingRecord');

const CheckInTotals = z
  .strictObject({ version: bodyVersion(1), ...checkInTotalsFields })
  .openapi('CheckInTotals');

/**
 * Signs a view URL for every photo of these check-ins, in one call to storage. A check-in whose
 * photo file is gone is logged, and `wire` leaves that photo out rather than failing the list.
 */
async function viewUrls(
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
 * 练了 by day for 我's training record.
 */
export function checkIns(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
  readonly photos: PhotoStorage;
  readonly log: Log;
  /** Has the squads' coaches look at a new check-in; left out, they look when the coach job runs. */
  readonly coachLook?: CoachLooker | undefined;
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
          'a 请假条 for a day the member trained on (`ALREADY_TRAINED`), or with a photo that ' +
          'isn’t uploaded',
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
      'leaves out are deleted. Teammates’ reactions and comments stay.',
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
        'Not a valid edit, of another kind than the check-in (`CHECK_IN_KIND_CHANGED`), or ' +
          'with a photo that isn’t uploaded',
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
      'Only for members of the squad.',
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

  const trainings = createRoute({
    method: 'get',
    path: '/me/trainings',
    operationId: 'listMyTrainings',
    summary: 'The signed-in member’s 练了 for a range of days, for their training record',
    description:
      '训练记录 on 我: each 练了 the member posted for a day in the range, wherever it went, ' +
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
      // The coaches reply while the request runs, since the server has CPU only then; the app
      // sends check-ins from its outbox, so nobody waits on it.
      if (created && checkIn.audience.length > 0 && deps.coachLook !== undefined) {
        await coachLooksAtCheckIn(
          { look: deps.coachLook, log: deps.log },
          { checkIn: checkIn.id, squads: checkIn.audience },
        );
      }
      return created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(edit, async (c) => {
      const checkIn = await deps.checkIns.edit({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
        edit: c.req.valid('json'),
      });
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
            ...installedBuildsReplies,
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
      const counts = await deps.checkIns.totals(MemberId.parse(c.var.caller.userId));
      return c.json({ version: 1 as const, ...counts }, 200);
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
