import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';

import {
  FuelSuggestion,
  MemberId as CheckInMember,
  SquadId as CheckInSquad,
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
} from '@wildcard/check-ins';
import { SquadId } from '@wildcard/coach';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import { createPostgresSquadStore, createSquads, randomInviteCodes } from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { memberCalendar } from '../member-calendar.js';
import { config, scenesOn, signUp } from '../test-kit/local-supabase.js';
import { FUEL_WORDS, coachSquadWeek } from './coach.js';

// The coach reads a suggested 饮食小目标 in the words the member picked it by, so they stay the
// app's: ScheduleUI's String Catalog, `fuel.<suggestion>`, in Simplified Chinese.
const catalogFile = new URL(
  '../../../../../ios/Packages/Schedule/Sources/ScheduleUI/Resources/Localizable.xcstrings',
  import.meta.url,
);
const Catalog = z.object({
  strings: z.record(
    z.string(),
    z.object({
      localizations: z
        .record(z.string(), z.object({ stringUnit: z.object({ value: z.string() }).optional() }))
        .optional(),
    }),
  ),
});
const catalog = Catalog.parse(JSON.parse(readFileSync(catalogFile, 'utf8'))).strings;

describe('the coach’s 饮食小目标 words', () => {
  it.each(FuelSuggestion.options)('%s reads as the app shows it', (suggestion) => {
    expect(FUEL_WORDS[suggestion]).toBe(
      catalog[`fuel.${suggestion}`]?.localizations?.['zh-Hans']?.stringUnit?.value,
    );
  });
});

// The squad's week the coach reads, end to end on local Supabase: when each post went up on its
// author's own clock, and who reacted, in the order they did. Its week is in early August, apart
// from other tests'.
describe('the squad’s week as the coach reads it', () => {
  const db = createDatabase(config.databaseUrl);
  afterAll(() => db.destroy());
  const members = createMembers({ store: createPostgresProfileStore(db) });
  const squads = createSquads({
    store: createPostgresSquadStore(db),
    inviteCodes: randomInviteCodes,
    aiConsent: () => Promise.resolve(true),
  });
  const sports = createSports({ store: createPostgresSportStore(db) });
  const now = new Date('2026-08-06T12:00:00.000Z');
  const checkIns = createCheckIns({
    squadPlaceOf: () => Promise.resolve(false),
    sports,
    store: createPostgresCheckInStore(db),
    membership: squads,
    reactions: createPostgresReactionStore(db),
    comments: createPostgresCommentStore(db),
    plans: createPostgresWeeklyPlanStore(db),
    photos: createSupabasePhotoStorage({
      supabaseUrl: config.supabaseUrl,
      secretKey: config.supabaseSecretKey,
    }),
    calendarOf: memberCalendar(members),
    clock: () => now,
  });

  it('says when each post went up on its author’s clock, and who reacted', async () => {
    const [shanghai, newYork, noProfile] = await Promise.all([signUp(), signUp(), signUp()]);
    const squad = randomUUID();
    const made = '2026-07-01T00:00:00.000Z';
    // An invite code from the squad's id, in the codes' letters.
    const inviteCode = Array.from(squad.replaceAll('-', '').slice(0, 8), (digit) =>
      '23456789ABCDEFGH'.charAt(Number.parseInt(digit, 16)),
    ).join('');
    await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
      values (${squad}, '夜猫子', ${inviteCode},
        ${shanghai.userId}, ${shanghai.userId}, ${made})`.execute(db);
    for (const person of [shanghai, newYork, noProfile]) {
      await sql`insert into public.squad_members (squad_id, member_id, joined_at)
        values (${squad}, ${person.userId}, ${made})`.execute(db);
      await sql`insert into public.squad_membership_events (squad_id, member_id, kind, actor_id, at)
        values (${squad}, ${person.userId}, 'joined', ${person.userId}, ${made})`.execute(db);
    }
    await sql`insert into public.profiles (member_id, time_zone)
      values (${shanghai.userId}, 'Asia/Shanghai'), (${newYork.userId}, 'America/New_York')`.execute(
      db,
    );
    const post = async ({ member, day, at }: { member: string; day: string; at: string }) => {
      const id = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${id}, ${member}, ${day}, ${at}, 'trained', '{"version":1,"sport":"run"}')`.execute(
        db,
      );
      await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
        values (${id}, ${squad}, 1)`.execute(db);
      return id;
    };
    // 23:40 on Tuesday in Shanghai; 05:10 on Wednesday in New York; no zone for the third.
    const late = await post({
      member: shanghai.userId,
      day: '2026-08-04',
      at: '2026-08-04T15:40:00.000Z',
    });
    await post({ member: newYork.userId, day: '2026-08-05', at: '2026-08-05T09:10:00.000Z' });
    await post({ member: noProfile.userId, day: '2026-08-05', at: '2026-08-05T10:00:00.000Z' });
    await sql`insert into public.check_in_reactions (check_in_id, member_id, emoji, reacted_at)
      values (${late}, ${noProfile.userId}, '🔥', '2026-08-05T01:00:00.000Z'),
        (${late}, ${newYork.userId}, '👏', '2026-08-04T16:00:00.000Z')`.execute(db);

    const week = await coachSquadWeek({
      checkIns,
      members,
      squads,
      sports,
      scenes: scenesOn(db),
      clock: () => now,
    })({ squad: SquadId.parse(squad), weekStart: '2026-08-03' });
    expect(
      week.checkIns.map(({ member, postedTime, reactedBy }) => ({ member, postedTime, reactedBy })),
    ).toStrictEqual([
      {
        member: shanghai.userId,
        postedTime: '23:40',
        reactedBy: [newYork.userId, noProfile.userId],
      },
      { member: newYork.userId, postedTime: '05:10', reactedBy: [] },
      { member: noProfile.userId, postedTime: undefined, reactedBy: [] },
    ]);
  });

  it('reads a tagged place’s name, never its coordinates, and none on a post only recorded', async () => {
    const me = await signUp();
    const squad = randomUUID();
    const made = '2026-07-01T00:00:00.000Z';
    const inviteCode = Array.from(squad.replaceAll('-', '').slice(0, 8), (digit) =>
      '23456789ABCDEFGH'.charAt(Number.parseInt(digit, 16)),
    ).join('');
    await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
      values (${squad}, '沙拉', ${inviteCode}, ${me.userId}, ${me.userId}, ${made})`.execute(db);
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${squad}, ${me.userId}, ${made})`.execute(db);
    await sql`insert into public.squad_membership_events (squad_id, member_id, kind, actor_id, at)
      values (${squad}, ${me.userId}, 'joined', ${me.userId}, ${made})`.execute(db);
    const payload = JSON.stringify({
      version: 1,
      caption: '沙拉',
      place: { name: 'Sweetgreen', latitude: 40.7448, longitude: -73.9881 },
    });
    const post = async ({ at, inFeed }: { at: string; inFeed: boolean }) => {
      const id = randomUUID();
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload, in_feed)
        values (${id}, ${me.userId}, '2026-08-04', ${at}, 'healthyMeal', ${payload}::jsonb, ${inFeed})`.execute(
        db,
      );
      await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
        values (${id}, ${squad}, 1)`.execute(db);
    };
    await post({ at: '2026-08-04T12:00:00.000Z', inFeed: true });
    await post({ at: '2026-08-04T18:00:00.000Z', inFeed: false });

    const week = await coachSquadWeek({
      checkIns,
      members,
      squads,
      sports,
      scenes: scenesOn(db),
      clock: () => now,
    })({ squad: SquadId.parse(squad), weekStart: '2026-08-03' });
    expect(week.checkIns.map(({ place, text }) => ({ place, text }))).toStrictEqual([
      { place: 'Sweetgreen', text: '沙拉' },
      { place: undefined, text: undefined },
    ]);
    expect(JSON.stringify(week)).not.toContain('40.7448');
  });

  it('counts only what a member shared to the squad, never a post kept to themselves', async () => {
    const me = await signUp();
    const squad = randomUUID();
    const made = '2026-07-01T00:00:00.000Z';
    const inviteCode = Array.from(squad.replaceAll('-', '').slice(0, 8), (digit) =>
      '23456789ABCDEFGH'.charAt(Number.parseInt(digit, 16)),
    ).join('');
    await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
      values (${squad}, '私密', ${inviteCode}, ${me.userId}, ${me.userId}, ${made})`.execute(db);
    const post = async ({ day, kind, shared }: { day: string; kind: string; shared: boolean }) => {
      const id = randomUUID();
      const payload = kind === 'trained' ? '{"version":1,"sport":"swim"}' : '{"version":1}';
      await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
        values (${id}, ${me.userId}, ${day}, ${`${day}T12:00:00.000Z`}, ${kind}, ${payload}::jsonb)`.execute(
        db,
      );
      if (shared) {
        await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
          values (${id}, ${squad}, 1)`.execute(db);
      }
    };
    await post({ day: '2026-08-03', kind: 'trained', shared: true });
    await post({ day: '2026-08-04', kind: 'trained', shared: false });
    await post({ day: '2026-08-05', kind: 'trained', shared: false });
    await post({ day: '2026-08-04', kind: 'healthyMeal', shared: false });

    const member = CheckInMember.parse(me.userId);
    expect(await checkIns.totals(member)).toMatchObject({ trainedDays: 3, healthyMeals: 1 });
    expect(
      await checkIns.totalsSharedTo({ member, squad: CheckInSquad.parse(squad) }),
    ).toStrictEqual({
      trainedDays: 1,
      healthyMeals: 0,
      cheatMeals: 0,
      disclaimers: 0,
      topSport: { sport: 'swim', checkIns: 1 },
    });
  });
});
