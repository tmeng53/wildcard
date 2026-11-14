import {
  placeOf,
  type CheckInRecord,
  type MemberId,
  type Place,
  type SportKey,
} from '@wildcard/check-ins';
import { placeKey } from '@wildcard/place-ids';
import type { PlaceKey } from '@wildcard/places';

// A squad's places (地点页, 小队地图), worked out from the posts in its 动态 tagged with one
// (Tracy, 2026-11-12): nothing about a place is kept apart from them. Places get no score of their
// own (Tracy, 2026-11-13); a meal's 健康 and 好吃 are on the meal.

/** A place a squad's posts were tagged with, as its 地点页 and 小队地图 show it. */
export interface PlaceSummary {
  readonly key: PlaceKey;
  /** As the newest post there tagged it. */
  readonly place: Place;
  /** How many posts in the squad's 动态 were tagged with it (小队来过 N 次). */
  readonly visits: number;
  /** How many people posted them (来过的队友 N 人). */
  readonly people: number;
  readonly lastAt: Date;
  /** Who posted there and how many times, most first (小队地图's heads). */
  readonly members: readonly { readonly member: MemberId; readonly visits: number }[];
  /** 大家在这里练: each sport its 训练 named, most first. */
  readonly sports: readonly {
    readonly sport: SportKey;
    readonly customSport: string | undefined;
    readonly count: number;
  }[];
  /** 大家在这里吃: how many of its posts were each kind of meal. */
  readonly meals: { readonly healthyMeal: number; readonly cheatMeal: number };
}

/** A place's own page: its summary and what the squad did there. */
export interface PlaceDetail extends PlaceSummary {
  /** The posts tagged with it, newest first. */
  readonly posts: readonly CheckInRecord[];
}

/**
 * The key the place a post was tagged with goes by: a squad's own place by its id, else Maps'
 * by Maps' id; undefined for one Maps gave no id.
 */
export function keyOf(record: CheckInRecord): PlaceKey | undefined {
  const place = placeOf(record);
  return place === undefined ? undefined : placeKey(place);
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

/** A place's summary from its posts (newest first, at least one). */
export function summaryOf({
  key,
  posts,
}: {
  readonly key: PlaceKey;
  readonly posts: readonly CheckInRecord[];
}): PlaceSummary {
  const [newest] = posts;
  const place = newest === undefined ? undefined : placeOf(newest);
  if (newest === undefined || place === undefined) throw new Error('A place has a post');
  const members = new Map<MemberId, number>();
  const sports = new Map<
    string,
    { sport: SportKey; customSport: string | undefined; count: number }
  >();
  let healthyMeal = 0;
  let cheatMeal = 0;
  for (const post of posts) {
    members.set(post.member, (members.get(post.member) ?? 0) + 1);
    switch (post.kind) {
      case 'trained': {
        const { sport, customSport } = post.training;
        const name = `${sport}\n${customSport ?? ''}`;
        const seen = sports.get(name) ?? { sport, customSport, count: 0 };
        sports.set(name, { ...seen, count: seen.count + 1 });
        break;
      }
      case 'healthyMeal':
        healthyMeal += 1;
        break;
      case 'cheatMeal':
        cheatMeal += 1;
        break;
      case 'disclaimer':
        break;
    }
  }
  return {
    key,
    place,
    visits: posts.length,
    people: members.size,
    lastAt: newest.createdAt,
    members: [...members]
      .map(([member, visits]) => ({ member, visits }))
      .sort((a, b) => b.visits - a.visits),
    sports: [...sports.values()].sort((a, b) => b.count - a.count),
    meals: { healthyMeal, cheatMeal },
  };
}

/** A place's page from its posts (newest first, at least one). */
export function detailOf({
  key,
  posts,
}: {
  readonly key: PlaceKey;
  readonly posts: readonly CheckInRecord[];
}): PlaceDetail {
  return { ...summaryOf({ key, posts }), posts };
}
