import { describe, expect, it } from 'vitest';

import { CheckInId, Meal, MemberId, Training, type CheckInRecord } from './check-in.js';
import { menuOf, placeVisitsOf } from './week-places.js';

const GYM = { name: '星光健身', appleId: 'I1A2B3C4D5E6F', latitude: 40.74, longitude: -73.99 };
const PARK = { name: '河边公园', appleId: 'I9F8E7D6C5B4A', latitude: 40.7, longitude: -74.01 };
const OWN = {
  name: '楼下跳绳',
  squadPlaceId: '0f0f0f0f-0000-4000-8000-000000000001',
  latitude: 40.7,
  longitude: -74,
};

const PHOTO = '00000000-0000-4000-8000-00000000f070';
let made = 0;
/** A member's id from a letter: `a` is …0a. */
const who = (letter: string) => MemberId.parse(`00000000-0000-4000-8000-0000000000${letter}0`);
const base = ({
  member,
  day,
  inFeed = true,
}: {
  member: string;
  day: string;
  inFeed?: boolean;
}) => {
  made += 1;
  return {
    id: CheckInId.parse(`00000000-0000-4000-9000-${String(made).padStart(12, '0')}`),
    member: who(member),
    day,
    createdAt: new Date(Date.UTC(2026, 9, 19, 0, made)),
    inFeed,
    audience: [],
  };
};
const meal = (
  member: string,
  {
    rating,
    inFeed,
    caption,
  }: { rating?: { healthy: number; tasty: number }; inFeed?: boolean; caption?: string } = {},
): CheckInRecord => ({
  ...base({ member, day: '2026-10-20', ...(inFeed === undefined ? {} : { inFeed }) }),
  kind: 'healthyMeal',
  meal: Meal.parse({
    ...(rating === undefined ? {} : { rating }),
    ...(caption === undefined ? {} : { caption }),
    photos: [{ path: `${who(member)}/${PHOTO}` }],
  }),
});
const trained = (
  member: string,
  { day, place, inFeed }: { day: string; place?: object; inFeed?: boolean },
): CheckInRecord => ({
  ...base({ member, day, ...(inFeed === undefined ? {} : { inFeed }) }),
  kind: 'trained',
  training: Training.parse({ sport: 'run', ...(place === undefined ? {} : { place }) }),
});

describe('小队菜单', () => {
  it('shows the best 卡价比 first, then the better 健康, then the latest, at most 3', () => {
    const menu = menuOf([
      meal('a', { rating: { healthy: 4, tasty: 5 }, caption: '沙拉' }), // 4
      meal('b', { rating: { healthy: 5, tasty: 4 } }), // 4, healthier
      meal('c', { rating: { healthy: 2, tasty: 5 } }), // 2
      meal('d', { rating: { healthy: 5, tasty: 5 } }), // 5
      meal('e', { rating: { healthy: 4, tasty: 5 } }), // 4, later than a
    ]);
    expect(menu.map(({ author }) => author)).toStrictEqual([who('d'), who('b'), who('e')]);
    expect(menu[0]?.photo).toBe(`${who('d')}/${PHOTO}`);
  });

  it('leaves out meals not rated or not posted, and keeps a meal’s caption', () => {
    const menu = menuOf([
      meal('a'),
      meal('b', { rating: { healthy: 5, tasty: 5 }, inFeed: false }),
      meal('c', { rating: { healthy: 1, tasty: 1 }, caption: '泡面' }),
      trained('d', { day: '2026-10-20' }),
    ]);
    expect(menu.map(({ author, caption }) => [author, caption])).toStrictEqual([
      [who('c'), '泡面'],
    ]);
  });
});

describe('the places the squad trained at', () => {
  it('puts the most 训练 first, then the most people, then the first trained at', () => {
    const places = placeVisitsOf([
      trained('a', { day: '2026-10-22', place: PARK }),
      trained('a', { day: '2026-10-23', place: PARK }),
      trained('b', { day: '2026-10-21', place: GYM }),
      trained('c', { day: '2026-10-20', place: GYM }),
      trained('a', { day: '2026-10-19', place: OWN }),
      trained('a', { day: '2026-10-24', place: OWN }),
      trained('b', {
        day: '2026-10-25',
        place: { name: '没有编号', latitude: 40.7, longitude: -74 },
      }),
      trained('c', { day: '2026-10-25', place: PARK, inFeed: false }),
    ]);
    expect(places.map(({ key, visits }) => [key, visits.length])).toStrictEqual([
      ['apple:I1A2B3C4D5E6F', 2],
      [`squad:${OWN.squadPlaceId}`, 2],
      ['apple:I9F8E7D6C5B4A', 2],
    ]);
    expect(places[0]?.visits.map(({ member, day }) => ({ member, day }))).toStrictEqual([
      { member: who('c'), day: '2026-10-20' },
      { member: who('b'), day: '2026-10-21' },
    ]);
  });

  it('keeps the place as its latest 训练 there tagged it', () => {
    const [place] = placeVisitsOf([
      trained('a', { day: '2026-10-20', place: GYM }),
      trained('b', { day: '2026-10-21', place: { ...GYM, name: '星光健身（新店）' } }),
    ]);
    expect(place?.place.name).toBe('星光健身（新店）');
  });
});
