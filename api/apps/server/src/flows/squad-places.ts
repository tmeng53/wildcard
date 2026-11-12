import {
  calorieValue,
  placeOf,
  type CheckInRecord,
  type MemberId,
  type Place,
  type SportKey,
} from '@wildcard/check-ins';
import { appleKey, squadKey, type PlaceKey, type Stars } from '@wildcard/places';

// A squad's places (地点页, 小队地图), worked out from the posts in its 动态 tagged with one and
// its members' scores (Tracy, 2026-11-12): nothing about a place is kept apart from them.

/** A place a squad's posts were tagged with, as its 地点页 and 小队地图 show it. */
export interface PlaceSummary {
  readonly key: PlaceKey;
  /** As the newest post there tagged it. */
  readonly place: Place;
  /** How many posts in the squad's 动态 were tagged with it (小队来过 N 次). */
  readonly visits: number;
  /** How many people posted them (来过的队友 N 人). */
  readonly people: number;
  /** The squad's members' scores, averaged to one decimal; undefined before anyone gave one. */
  readonly stars: number | undefined;
  /** How many of the squad's members gave one. */
  readonly raters: number;
  readonly lastAt: Date;
}

/** A place's own page: its summary and what the squad did there. */
export interface PlaceDetail extends PlaceSummary {
  /** The viewer's own score, standing; undefined before they give one. */
  readonly myStars: Stars | undefined;
  /** 大家在这里练: each sport its 训练 named, most first. */
  readonly sports: readonly {
    readonly sport: SportKey;
    readonly customSport: string | undefined;
    readonly count: number;
  }[];
  /** 大家在这里吃: its meals by kind, and their 健康, 好吃 and 卡价比 averaged over rated ones. */
  readonly meals: {
    readonly healthyMeal: number;
    readonly cheatMeal: number;
    readonly healthy: number | undefined;
    readonly tasty: number | undefined;
    readonly calorieValue: number | undefined;
  };
  /** The posts tagged with it, newest first. */
  readonly posts: readonly CheckInRecord[];
}

/**
 * The key the place a post was tagged with goes by: a squad's own place by its id, else Maps'
 * by Maps' id; undefined for one Maps gave no id.
 */
export function keyOf(record: CheckInRecord): PlaceKey | undefined {
  const place = placeOf(record);
  if (place?.squadPlaceId !== undefined) return squadKey(place.squadPlaceId);
  return place?.appleId === undefined ? undefined : appleKey(place.appleId);
}

/** The posts by place, each place's newest first, places in the order their newest came. */
export function byPlace(records: readonly CheckInRecord[]): Map<PlaceKey, CheckInRecord[]> {
  const places = new Map<PlaceKey, CheckInRecord[]>();
  for (const record of records) {
    const key = keyOf(record);
    if (key === undefined) continue;
    places.set(key, [...(places.get(key) ?? []), record]);
  }
  return places;
}

const oneDecimal = (value: number) => Math.round(value * 10) / 10;
const mean = (values: readonly number[]) =>
  values.length === 0
    ? undefined
    : oneDecimal(values.reduce((sum, each) => sum + each, 0) / values.length);

/** A place's summary from its posts (newest first, at least one) and members' scores. */
export function summaryOf({
  key,
  posts,
  scores,
}: {
  readonly key: PlaceKey;
  readonly posts: readonly CheckInRecord[];
  readonly scores: ReadonlyMap<MemberId, Stars>;
}): PlaceSummary {
  const [newest] = posts;
  const place = newest === undefined ? undefined : placeOf(newest);
  if (newest === undefined || place === undefined) throw new Error('A place has a post');
  return {
    key,
    place,
    visits: posts.length,
    people: new Set(posts.map((post) => post.member)).size,
    stars: mean([...scores.values()]),
    raters: scores.size,
    lastAt: newest.createdAt,
  };
}

/** A place's page from its posts (newest first, at least one), members' scores and the viewer. */
export function detailOf({
  key,
  posts,
  scores,
  viewer,
}: {
  readonly key: PlaceKey;
  readonly posts: readonly CheckInRecord[];
  readonly scores: ReadonlyMap<MemberId, Stars>;
  readonly viewer: MemberId;
}): PlaceDetail {
  const sports = new Map<
    string,
    { sport: SportKey; customSport: string | undefined; count: number }
  >();
  const rated: { healthy: number; tasty: number }[] = [];
  let healthyMeal = 0;
  let cheatMeal = 0;
  for (const post of posts) {
    switch (post.kind) {
      case 'trained': {
        const { sport, customSport } = post.training;
        const name = `${sport}\n${customSport ?? ''}`;
        const seen = sports.get(name) ?? { sport, customSport, count: 0 };
        sports.set(name, { ...seen, count: seen.count + 1 });
        break;
      }
      case 'healthyMeal':
      case 'cheatMeal':
        if (post.kind === 'healthyMeal') healthyMeal += 1;
        else cheatMeal += 1;
        if (post.meal.rating !== undefined) rated.push(post.meal.rating);
        break;
      case 'disclaimer':
        break;
    }
  }
  return {
    ...summaryOf({ key, posts, scores }),
    myStars: scores.get(viewer),
    sports: [...sports.values()].sort((a, b) => b.count - a.count),
    meals: {
      healthyMeal,
      cheatMeal,
      healthy: mean(rated.map((each) => each.healthy)),
      tasty: mean(rated.map((each) => each.tasty)),
      calorieValue: mean(rated.map(calorieValue)),
    },
    posts,
  };
}
