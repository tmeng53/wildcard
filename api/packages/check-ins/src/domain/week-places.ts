import { placeKey, type Place, type PlaceKey } from '@wildcard/place-ids';

import type { CheckInId, CheckInRecord, LocalDay, MemberId } from './check-in.js';
import { calorieValue, type MealRating } from './meal-rating.js';

// The Sunday 战报's food and place pages (Tracy, 2026-11-12), without AI: 小队菜单, the meals the
// squad rated, best 卡价比 first, as a menu to try rather than a ranking; and the places the squad
// trained at, from which 小队最爱去 and 新发现 are read. Only posts count (发布到动态): a check-in
// only recorded is never on a page.

/** The most dishes 小队菜单 shows. */
export const MENU_MAX = 3;

/** A rated meal on 小队菜单. */
export interface MenuDish {
  readonly checkIn: CheckInId;
  readonly author: MemberId;
  readonly day: LocalDay;
  readonly rating: MealRating;
  /** The meal's line, which names the dish, when it had one. */
  readonly caption?: string;
  /** Its first photo's path, when it had one. */
  readonly photo?: string;
  /** Where it was eaten, when it was tagged with a place. */
  readonly place?: Place;
}

/** A place the squad trained at that week, and each 训练 there. */
export interface PlaceVisits {
  readonly key: PlaceKey;
  /** The place as its latest 训练 there was tagged with it. */
  readonly place: Place;
  /** Each 训练 there, the earliest first. */
  readonly visits: readonly { readonly member: MemberId; readonly day: LocalDay }[];
}

/**
 * 小队菜单: the week's rated meals posted, best 卡价比 first, then the better 健康, then the latest,
 * at most `MENU_MAX`. Each is its author's own post, kept with it.
 */
export function menuOf(checkIns: readonly CheckInRecord[]): MenuDish[] {
  const rated = checkIns.flatMap((each) => {
    if (!each.inFeed || (each.kind !== 'healthyMeal' && each.kind !== 'cheatMeal')) return [];
    const { rating, caption, photos, place } = each.meal;
    if (rating === undefined) return [];
    const photo = photos?.[0]?.path;
    const dish: MenuDish = {
      checkIn: each.id,
      author: each.member,
      day: each.day,
      rating,
      ...(caption === undefined ? {} : { caption }),
      ...(photo === undefined ? {} : { photo }),
      ...(place === undefined ? {} : { place }),
    };
    return [{ dish, made: each.createdAt.getTime() }];
  });
  return rated
    .toSorted(
      (a, b) =>
        calorieValue(b.dish.rating) - calorieValue(a.dish.rating) ||
        b.dish.rating.healthy - a.dish.rating.healthy ||
        b.made - a.made,
    )
    .slice(0, MENU_MAX)
    .map(({ dish }) => dish);
}

/**
 * The places the squad's 训练 posts were tagged with that week (one Maps could find again, or the
 * squad's own), the most 训练 first, then the most people, then the one first trained at.
 */
export function placeVisitsOf(checkIns: readonly CheckInRecord[]): PlaceVisits[] {
  const byKey = new Map<
    PlaceKey,
    { place: Place; visits: { member: MemberId; day: LocalDay }[] }
  >();
  const sorted = checkIns.toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  for (const each of sorted) {
    if (!each.inFeed || each.kind !== 'trained' || each.training.place === undefined) continue;
    const key = placeKey(each.training.place);
    if (key === undefined) continue;
    const found = byKey.get(key) ?? { place: each.training.place, visits: [] };
    found.place = each.training.place;
    found.visits.push({ member: each.member, day: each.day });
    byKey.set(key, found);
  }
  const people = (visits: readonly { member: MemberId }[]) =>
    new Set(visits.map(({ member }) => member)).size;
  return [...byKey.entries()]
    .map(([key, { place, visits }]) => ({
      key,
      place,
      visits: visits.toSorted((a, b) => a.day.localeCompare(b.day)),
    }))
    .toSorted(
      (a, b) =>
        b.visits.length - a.visits.length ||
        people(b.visits) - people(a.visits) ||
        (a.visits[0]?.day ?? '').localeCompare(b.visits[0]?.day ?? ''),
    );
}
