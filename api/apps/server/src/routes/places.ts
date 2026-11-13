import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  LocalDay,
  MemberId,
  Place,
  SportKey,
  SquadId,
  photosOf,
  type CheckInRecord,
  type CheckIns,
} from '@wildcard/check-ins';
import {
  PlaceKey,
  SquadPlaceFields,
  SquadPlaceId,
  type SquadPlace,
  type SquadPlaces,
} from '@wildcard/places';

import { bodyVersion } from '../body-version.js';
import {
  byPlace,
  detailOf,
  keyOf,
  summaryOf,
  type PlaceDetail,
  type PlaceSummary,
} from '../flows/squad-places.js';
import type { Log } from '../log.js';
import type { PhotoStorage, VerifyToken } from '../ports.js';
import { PhotoView, viewUrls } from './check-ins.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { PlaceNotFoundError } from '../errors.js';

/** How far back 小队地图's 今天 looks: the app keeps the posts of the viewer's own today. */
const RECENT_MS = 2 * 86_400_000;

/** A score's shape, kept only for replies older builds read: places have no score now. */
const Stars = z.int().min(1).max(5).meta({ description: 'The score, 1 to 5.' });

const placeKey = PlaceKey.meta({
  description: "Which place: `apple:` and Apple Maps' identifier, as the post's place carries it.",
});

const summaryFields = {
  key: placeKey,
  place: Place.meta({ description: 'The place as the newest post there tagged it.' }),
  visits: z
    .int()
    .min(1)
    .meta({ description: '小队来过 N 次: posts in the squad’s 动态 tagged with it.' }),
  people: z.int().min(1).meta({ description: '来过的队友 N 人: how many people posted them.' }),
  stars: z
    .number()
    .min(1)
    .max(5)
    .nullable()
    .meta({
      description:
        'No longer given: places have no score (Tracy, 2026-11-13). Always null, kept for ' +
        'builds that read it.',
    }),
  raters: z.int().min(0).meta({ description: 'No longer given: always 0.' }),
  lastAt: z.iso.datetime().meta({ description: 'When the newest post there was made, in UTC.' }),
  members: z
    .array(
      z.strictObject({
        member: z.uuid(),
        visits: z.int().min(1).meta({ description: 'How many of the posts there are theirs.' }),
      }),
    )
    .meta({
      description:
        '小队地图’s heads: who posted there, most posts first; one who left the squad is ' +
        'still listed, for the app to grey.',
    }),
  sports: z
    .array(
      z.strictObject({
        sport: SportKey,
        customSport: z.string().optional(),
        count: z.int().min(1),
      }),
    )
    .meta({ description: '大家在这里练: each sport its 训练 named, most first.' }),
  meals: z
    .strictObject({ healthyMeal: z.int().min(0), cheatMeal: z.int().min(0) })
    .meta({ description: '大家在这里吃: how many of its posts were each kind of meal.' }),
};

const Visit = z
  .strictObject({
    checkIn: z.uuid(),
    member: z.uuid().meta({ description: 'Who posted it.' }),
    kind: z.enum(['trained', 'healthyMeal', 'cheatMeal']),
    sport: SportKey.optional().meta({ description: 'A 训练’s sport.' }),
    customSport: z.string().optional().meta({ description: 'A custom sport’s name.' }),
    day: LocalDay,
    createdAt: z.iso.datetime(),
    key: placeKey,
    cover: PhotoView.optional().meta({
      description:
        'The post’s first photo, for its tile; missing when it has none (or its file is gone).',
    }),
    minutes: z.int().min(1).optional().meta({ description: 'A 训练’s minutes, when it has them.' }),
    stars: Stars.nullable().meta({
      description: 'No longer given: always null (places have no score, Tracy 2026-11-13).',
    }),
    calorieValue: z.number().min(0.2).max(5).nullable().meta({
      description: 'No longer given: always null (a place’s tiles show no score).',
    }),
  })
  .openapi('PlaceVisit');

const SquadPlaces = z
  .strictObject({
    version: bodyVersion(1),
    places: z
      .array(z.strictObject(summaryFields).openapi('PlaceSummary'))
      .meta({ description: '小队地图’s 常去: every place, most visited first.' }),
    recent: z.array(Visit).meta({
      description:
        'Posts tagged with a place in the last two days, newest first: 小队地图’s 今天 shows ' +
        'those of the viewer’s own today.',
    }),
  })
  .openapi('SquadPlaces');

const PlaceDetailView = z
  .strictObject({
    version: bodyVersion(1),
    ...summaryFields,
    meals: z
      .strictObject({
        healthyMeal: z.int().min(0),
        cheatMeal: z.int().min(0),
        healthy: z.number().nullable().meta({ description: 'No longer given: always null.' }),
        tasty: z.number().nullable().meta({ description: 'No longer given: always null.' }),
        calorieValue: z.number().nullable().meta({ description: 'No longer given: always null.' }),
      })
      .meta({
        description:
          '大家在这里吃: meals by kind. Places show no averages of meals’ scores (Tracy, ' +
          '2026-11-13); a meal keeps its own 健康 and 好吃.',
      }),
    myStars: Stars.nullable().meta({ description: 'No longer given: always null.' }),
    posts: z.array(Visit).meta({ description: '动态: the posts tagged with it, newest first.' }),
  })
  .openapi('PlaceDetail');

const SquadPlaceView = z
  .strictObject({
    id: SquadPlaceId,
    ...SquadPlaceFields,
    addedBy: z
      .uuid()
      .nullable()
      .meta({ description: 'Who added it; null once they deleted their account.' }),
    addedAt: z.iso.datetime(),
  })
  .meta({
    description:
      "A place one of the squad's members added. A post tags it with the place's " +
      '`squadPlaceId`, `name` and coordinates.',
  })
  .openapi('SquadPlace');

const SquadPlaceList = z
  .strictObject({
    version: bodyVersion(1),
    places: z.array(SquadPlaceView).meta({ description: 'The earliest added first.' }),
  })
  .openapi('SquadPlaceList');

const SquadPlaceAdded = z
  .strictObject({ version: bodyVersion(1), place: SquadPlaceView })
  .openapi('SquadPlaceAdded');

const SquadPlaceChange = z
  .strictObject({ version: bodyVersion(1), ...SquadPlaceFields })
  .openapi('SquadPlaceChange');

function wireSquadPlace(place: SquadPlace): z.infer<typeof SquadPlaceView> {
  return {
    id: place.id,
    name: place.name,
    kind: place.kind,
    latitude: place.latitude,
    longitude: place.longitude,
    addedBy: place.addedBy ?? null,
    addedAt: place.addedAt.toISOString(),
  };
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** What a post's tile needs besides the post: its place and the photo URLs. */
interface VisitContext {
  readonly key: PlaceKey;
  readonly urls: Awaited<ReturnType<typeof viewUrls>>;
}

function visitOf(record: CheckInRecord, at: VisitContext): z.infer<typeof Visit> | undefined {
  const [first] = photosOf(record);
  const url = first === undefined ? undefined : at.urls.get(first.path);
  const cover =
    first === undefined || url === undefined
      ? {}
      : {
          cover: {
            path: first.path,
            url: url.href,
            ...(first.size === undefined ? {} : { size: first.size }),
          },
        };
  const base = {
    checkIn: record.id,
    member: record.member,
    day: record.day,
    createdAt: record.createdAt.toISOString(),
    key: at.key,
    ...cover,
  };
  switch (record.kind) {
    case 'trained':
      return {
        ...base,
        kind: 'trained',
        sport: record.training.sport,
        ...(record.training.customSport === undefined
          ? {}
          : { customSport: record.training.customSport }),
        ...(record.training.minutes === undefined ? {} : { minutes: record.training.minutes }),
        stars: null,
        calorieValue: null,
      };
    case 'healthyMeal':
    case 'cheatMeal': {
      return {
        ...base,
        kind: record.kind,
        stars: null,
        calorieValue: null,
      };
    }
    case 'disclaimer':
      return undefined;
  }
}

function wireSummary(summary: PlaceSummary) {
  return {
    key: summary.key,
    place: summary.place,
    visits: summary.visits,
    people: summary.people,
    stars: null,
    raters: 0,
    lastAt: summary.lastAt.toISOString(),
    members: summary.members.map(({ member, visits }) => ({ member, visits })),
    sports: summary.sports.map(({ sport, customSport, count }) => ({
      sport,
      ...(customSport === undefined ? {} : { customSport }),
      count,
    })),
    meals: { healthyMeal: summary.meals.healthyMeal, cheatMeal: summary.meals.cheatMeal },
  };
}

function wireDetail(
  detail: PlaceDetail,
  at: Omit<VisitContext, 'key'>,
): z.infer<typeof PlaceDetailView> {
  return {
    version: 1,
    ...wireSummary(detail),
    meals: {
      healthyMeal: detail.meals.healthyMeal,
      cheatMeal: detail.meals.cheatMeal,
      healthy: null,
      tasty: null,
      calorieValue: null,
    },
    myStars: null,
    posts: detail.posts.flatMap((post) => visitOf(post, { ...at, key: detail.key }) ?? []),
  };
}

/**
 * A squad's places (地点页, 小队地图) and the places its members added. It spans modules: the
 * check-ins keep the posts tagged with a place, the places module the squad's own places.
 */
export function places(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: Pick<CheckIns, 'placedPosts'>;
  readonly photos: PhotoStorage;
  readonly log: Log;
  readonly squadPlaces: SquadPlaces;
  readonly clock?: () => Date;
}) {
  const clock = deps.clock ?? (() => new Date());

  const list = createRoute({
    method: 'get',
    path: '/squads/{squadId}/places',
    operationId: 'listSquadPlaces',
    summary: 'The places the squad’s posts were tagged with (小队地图)',
    description:
      'Only posts in the squad’s 动态 count, never where anyone’s phone was. Scores are the ' +
      'squad’s current members’.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: { description: 'The places', content: { 'application/json': { schema: SquadPlaces } } },
      400: problem('Not a valid squad id'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/places/{key}',
    operationId: 'getSquadPlace',
    summary: 'One place’s page (地点页)',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId, key: placeKey }) },
    responses: {
      200: {
        description: 'The place',
        content: { 'application/json': { schema: PlaceDetailView } },
      },
      400: problem('Not a valid squad id or place'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem(
        'No post in the squad’s 动态 was tagged with it (`PLACE_NOT_FOUND`): the app shows the ' +
          'place empty. A caller not in the squad gets 403, never 404.',
      ),
      ...signedInFailures,
    },
  });

  const listAdded = createRoute({
    method: 'get',
    path: '/squads/{squadId}/custom-places',
    operationId: 'listSquadCustomPlaces',
    summary: 'The places the squad’s members added themselves (自建地点)',
    description: 'What the place picker lists beside Apple Maps’ places, for every member to tag.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: {
        description: 'The places',
        content: { 'application/json': { schema: SquadPlaceList } },
      },
      400: problem('Not a valid squad id'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const add = createRoute({
    method: 'put',
    path: '/squads/{squadId}/custom-places/{placeId}',
    operationId: 'addSquadCustomPlace',
    summary: 'Add a place for the squad (新建地点), under an id the app made',
    description:
      'The whole squad sees it, and anyone in it may tag their posts with it. It never ' +
      'changes; the same place again changes nothing, so it is safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId, placeId: SquadPlaceId }),
      body: { required: true, content: { 'application/json': { schema: SquadPlaceChange } } },
    },
    responses: {
      201: {
        description: 'Added',
        content: { 'application/json': { schema: SquadPlaceAdded } },
      },
      200: {
        description: 'Already added, as it was',
        content: { 'application/json': { schema: SquadPlaceAdded } },
      },
      400: problem('Not a valid place'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      409: problem('The id is already another place (`SQUAD_PLACE_ID_CONFLICT`)'),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(listAdded, async (c) => {
      const { squadId } = c.req.valid('param');
      const viewer = MemberId.parse(c.var.caller.userId);
      const added = await deps.squadPlaces.list({ squad: squadId, viewer });
      return c.json({ version: 1 as const, places: added.map(wireSquadPlace) }, 200);
    })
    .openapi(add, async (c) => {
      const { squadId, placeId } = c.req.valid('param');
      const { name, kind, latitude, longitude } = c.req.valid('json');
      const member = MemberId.parse(c.var.caller.userId);
      const { place, created } = await deps.squadPlaces.add({
        id: placeId,
        squad: squadId,
        member,
        name,
        kind,
        latitude,
        longitude,
      });
      const body = { version: 1 as const, place: wireSquadPlace(place) };
      return created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(list, async (c) => {
      const { squadId } = c.req.valid('param');
      const viewer = MemberId.parse(c.var.caller.userId);
      const posts = await deps.checkIns.placedPosts({ squad: squadId, viewer });
      const grouped = byPlace(posts);
      const summaries = [...grouped].map(([key, each]) => summaryOf({ key, posts: each }));
      summaries.sort((a, b) => b.visits - a.visits || b.lastAt.getTime() - a.lastAt.getTime());
      const since = clock().getTime() - RECENT_MS;
      const latest = posts.filter((post) => post.createdAt.getTime() >= since);
      const urls = await viewUrls(deps, latest);
      const recent = latest.flatMap((post) => {
        const key = keyOf(post);
        if (key === undefined) return [];
        return visitOf(post, { key, urls }) ?? [];
      });
      return c.json({ version: 1 as const, places: summaries.map(wireSummary), recent }, 200);
    })
    .openapi(read, async (c) => {
      const { squadId, key } = c.req.valid('param');
      const viewer = MemberId.parse(c.var.caller.userId);
      const posts = byPlace(await deps.checkIns.placedPosts({ squad: squadId, viewer })).get(key);
      if (posts === undefined) throw new PlaceNotFoundError(key);
      const urls = await viewUrls(deps, posts);
      return c.json(wireDetail(detailOf({ key, posts }), { urls }), 200);
    });
}
