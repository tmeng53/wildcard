import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CheckInDraft,
  CheckInId,
  DayRange,
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
  type PhotoRef,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { PhotoStorage, VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { ReactionEntry, wireReaction } from './reactions.js';

const checkInFields = {
  version: bodyVersion(1),
  id: z.uuid(),
  member: z.uuid().meta({ description: 'The member who made it.' }),
  day: LocalDay.meta({
    description:
      'The member’s local day it counts for, in their profile’s time zone, where a day runs to 3am: their day at `createdAt` or the day before.',
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
  .strictObject({ ...storedTrainingFields, ...photoViews })
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

/** A squad's check-ins, each with what teammates left on it. */
const SquadPostList = z
  .strictObject({
    version: bodyVersion(1),
    posts: z.array(
      z
        .strictObject({
          checkIn: CheckIn,
          reactions: z
            .array(ReactionEntry)
            .meta({ description: 'Teammates’ emoji, oldest first.' }),
        })
        .openapi('SquadPost'),
    ),
  })
  .openapi('SquadPostList');

/**
 * Installed builds from before the replies were removed (#180) still require `replies` on each
 * post and fail to read the whole feed without it, so every post keeps an empty one. It stays out
 * of the contract: newer builds ignore keys they don't know. Remove it once no installed build
 * predates #180.
 */
const installedBuildsReplies: { readonly replies: readonly never[] } = { replies: [] };

const count = (description: string) => z.int().nonnegative().meta({ description });

const CheckInTotals = z
  .strictObject({
    version: bodyVersion(1),
    trainedDays: count('Days with a 练了; several 练了 on one day count once.'),
    healthyMeals: count('健康餐 check-ins.'),
    cheatMeals: count('坦白放纵餐 check-ins.'),
    disclaimers: count('今日请假条 check-ins, at most one a day.'),
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
  })
  .openapi('CheckInTotals');

/** Signs a view URL for every photo of these check-ins, in one call to storage. */
async function viewUrls(photos: PhotoStorage, records: readonly CheckInRecord[]) {
  const paths = records.flatMap((record) => photosOf(record).map(({ path }) => path));
  return photos.createViewUrls(paths, PHOTO_VIEW_SECONDS);
}

type ViewUrls = Awaited<ReturnType<typeof viewUrls>>;

/** The check-in as the app reads it: each photo with the URL to view it. */
function wire(record: CheckInRecord, urls: ViewUrls) {
  const withUrls = <T extends { readonly photos?: readonly PhotoRef[] | undefined }>({
    photos,
    ...fields
  }: T) => {
    if (photos === undefined) return fields;
    const views = photos.map(({ path, size }) => {
      const url = urls.get(path);
      if (url === undefined) throw new Error(`No view URL was signed for ${path}.`);
      return size === undefined ? { path, url: url.href } : { path, url: url.href, size };
    });
    return { ...fields, photos: views };
  };
  const base = {
    version: 1 as const,
    id: record.id,
    member: record.member,
    day: record.day,
    createdAt: record.createdAt.toISOString(),
    audience: [...record.audience],
  };
  switch (record.kind) {
    case 'trained':
      return { ...base, kind: record.kind, training: withUrls(record.training) };
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
 * Daily check-ins: `PUT /check-ins/{id}` saves one, `GET /squads/{squadId}/check-ins` (the
 * squad's feed, with reactions) and `GET /me/check-ins` read them back for a range of
 * days, and `GET /me/check-in-totals` counts
 * all of the member's own.
 */
export function checkIns(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
  readonly photos: PhotoStorage;
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
          'counted for the wrong day, or with a photo that isn’t uploaded',
      ),
      403: problem('Sent to a squad the member isn’t in, or with someone else’s photo'),
      409: problem(
        'The id holds a different check-in, today’s disclaimer is already posted, or another ' +
          'check-in uses one of the photos',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const listForSquad = createRoute({
    method: 'get',
    path: '/squads/{squadId}/check-ins',
    operationId: 'listSquadCheckIns',
    summary: 'A squad’s check-ins for a range of days, with their reactions',
    description:
      'The squad’s feed: check-ins sent to the squad by members still in it, newest day first, ' +
      'each with the reactions of the teammates the viewer shares a squad with. ' +
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

  const listMine = createRoute({
    method: 'get',
    path: '/me/check-ins',
    operationId: 'listMyCheckIns',
    summary: 'The signed-in member’s check-ins for a range of days',
    description: 'Newest day first, each with its whole audience.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { query: DayRange },
    responses: {
      200: {
        description: 'The check-ins',
        content: { 'application/json': { schema: CheckInList } },
      },
      400: problem('Not a valid range of days (at most 31)'),
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

  return new OpenAPIHono<SignedIn>()
    .openapi(save, async (c) => {
      const { checkIn, created } = await deps.checkIns.save({
        id: c.req.valid('param').id,
        member: MemberId.parse(c.var.caller.userId),
        draft: c.req.valid('json'),
      });
      const body = wire(checkIn, await viewUrls(deps.photos, [checkIn]));
      return created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(listForSquad, async (c) => {
      const posts = await deps.checkIns.listForSquad({
        viewer: MemberId.parse(c.var.caller.userId),
        squad: c.req.valid('param').squadId,
        days: c.req.valid('query'),
      });
      const urls = await viewUrls(
        deps.photos,
        posts.map(({ checkIn }) => checkIn),
      );
      return c.json(
        {
          version: 1 as const,
          posts: posts.map(({ checkIn, reactions }) => ({
            checkIn: wire(checkIn, urls),
            reactions: reactions.map(wireReaction),
            ...installedBuildsReplies,
          })),
        },
        200,
      );
    })
    .openapi(listMine, async (c) => {
      const records = await deps.checkIns.listMine({
        member: MemberId.parse(c.var.caller.userId),
        days: c.req.valid('query'),
      });
      const urls = await viewUrls(deps.photos, records);
      return c.json(
        { version: 1 as const, checkIns: records.map((record) => wire(record, urls)) },
        200,
      );
    })
    .openapi(totals, async (c) => {
      const counts = await deps.checkIns.totals(MemberId.parse(c.var.caller.userId));
      return c.json({ version: 1 as const, ...counts }, 200);
    });
}
