import { randomUUID } from 'node:crypto';

import {
  createCheckIns,
  createPostgresCheckInStore,
  createPostgresCommentStore,
  createPostgresReactionStore,
  createPostgresWeeklyPlanStore,
} from '@wildcard/check-ins';
import { createMembers, createPostgresProfileStore } from '@wildcard/members';
import type { NewNotice } from '@wildcard/notices';
import {
  SquadId,
  createPostgresSquadStore,
  createSquads,
  randomInviteCodes,
} from '@wildcard/squads';
import { createPostgresSportStore, createSports } from '@wildcard/sports';
import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabasePhotoStorage } from '../adapters/supabase-storage.js';
import { createLog } from '../log.js';
import { memberCalendar } from '../member-calendar.js';
import { config, signUp } from '../test-kit/local-supabase.js';
import { suggestGoalIn, suggestSquadGoals } from './squad-goal-suggestion.js';

// The captain's goal suggestion end to end on local Supabase: squads, their goals and check-ins
// are real; the notices record what the captain would be told. Its weeks are in August, apart
// from every other test's, since a run reads every squad that trained in its week.
const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const members = createMembers({ store: createPostgresProfileStore(db) });
const squads = createSquads({
  store: createPostgresSquadStore(db),
  inviteCodes: randomInviteCodes,
  aiConsent: () => Promise.resolve(true),
});
/** Check-ins whose clock reads `now`, so each member's week is the one they are in then. */
const checkInsAt = (now: number) =>
  createCheckIns({
    sports: createSports({ store: createPostgresSportStore(db) }),
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
    clock: () => new Date(now),
  });

const DAY = 86_400_000;
// Monday 2026-07-27, three weeks before the week of 2026-08-17, whose 战报 froze on Sunday
// 2026-08-23 at 8pm in New York.
const FIRST = Date.parse('2026-07-27');
const FROZEN = Date.parse('2026-08-24T00:00:00.000Z');
const HOUR = 3_600_000;
/** The Monday of week `n`, counted from the first. */
const monday = (n: number) => new Date(FIRST + n * 7 * DAY).toISOString().slice(0, 10);

/** An invite code from a squad's id, in the codes' letters. */
const inviteCodeFor = (id: string) =>
  Array.from(id.replaceAll('-', '').slice(0, 8), (digit) =>
    '23456789ABCDEFGH'.charAt(Number.parseInt(digit, 16)),
  ).join('');

/** A squad of `size` members made before the first week, its first member the captain. */
async function squadOf(size: number) {
  const people = await Promise.all(Array.from({ length: size }, () => signUp()));
  const id = randomUUID();
  const made = new Date(FIRST - DAY).toISOString();
  const [captain] = people;
  if (captain === undefined) throw new Error('a squad needs a member');
  await sql`insert into public.squads (id, name, invite_code, created_by, captain_id, created_at)
    values (${id}, '狠人队', ${inviteCodeFor(id)},
      ${captain.userId}, ${captain.userId}, ${made})`.execute(db);
  for (const person of people) {
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${person.userId}, ${made})`.execute(db);
    await sql`insert into public.squad_membership_events (squad_id, member_id, kind, actor_id, at)
      values (${id}, ${person.userId}, 'joined', ${person.userId}, ${made})`.execute(db);
  }
  /** Each member trains on the first `days` days of week `n`, sent to the squad. */
  const train = async (n: number, days: number) => {
    for (const person of people) {
      for (let day = 0; day < days; day += 1) {
        const date = new Date(Date.parse(monday(n)) + day * DAY).toISOString().slice(0, 10);
        const checkIn = randomUUID();
        await sql`insert into public.check_ins (id, member_id, day, created_at, kind, payload)
          values (${checkIn}, ${person.userId}, ${date}, ${`${date}T12:00:00.000Z`}, 'trained',
            '{"version":1,"sport":"run"}')`.execute(db);
        await sql`insert into public.check_in_squads (check_in_id, squad_id, position)
          values (${checkIn}, ${id}, 1)`.execute(db);
      }
    }
  };
  return { id, people, captain, train };
}

/** While true, every notice a run tells is refused. */
let noticesDown = false;

/**
 * A run at `now`, with what it told this squad. The suggestion is kept on the real squads in a
 * transaction, as on the server; the notice is recorded, or refused while `noticesDown`.
 */
async function runAt(now: number, squad: string) {
  const told: NewNotice[] = [];
  const run = await suggestSquadGoals({
    checkIns: checkInsAt(now),
    squads,
    suggestGoal: suggestGoalIn(db, {
      squads: (scope) =>
        createSquads({
          store: createPostgresSquadStore(scope),
          inviteCodes: randomInviteCodes,
          aiConsent: () => Promise.resolve(true),
        }),
      notices: () => ({
        tell: (notices) => {
          if (noticesDown) return Promise.reject(new Error('notices are down'));
          told.push(...notices);
          return Promise.resolve([]);
        },
      }),
    }),
    clock: () => new Date(now),
    log: createLog(() => undefined),
  });
  return { run, told: told.filter((notice) => notice.squad === squad) };
}

describe('suggesting a captain a higher squad goal', () => {
  it('tells the captain once, after three weeks over the goal, the days each trained rounded', async () => {
    const squad = await squadOf(2);
    // Goal 3 a member (6 days for two); 4 days each is over, then 5 and 4: about 4.3 a member.
    await squad.train(1, 4);
    await squad.train(2, 5);
    await squad.train(3, 4);

    // Before the 战报 froze, the latest week is the one before, so nothing yet.
    expect((await runAt(FROZEN - HOUR, squad.id)).told).toEqual([]);
    const { run, told } = await runAt(FROZEN + HOUR, squad.id);
    expect(run.week).toBe(monday(3));
    expect(told).toEqual([
      {
        member: squad.captain.userId,
        squad: squad.id,
        kind: 'goalSuggestion',
        subject: { version: 1, weeks: 3, daysPerMember: 4 },
      },
    ]);
    // The hourly run after tells nobody again.
    expect((await runAt(FROZEN + 2 * HOUR, squad.id)).told).toEqual([]);

    // Still over the next week: the same run of weeks, so not again.
    await squad.train(4, 4);
    expect((await runAt(FROZEN + 7 * DAY + HOUR, squad.id)).told).toEqual([]);
  });

  it('counts only weeks over the goal, never one that just reached it', async () => {
    const squad = await squadOf(2);
    await squad.train(1, 4);
    // 3 days each is the goal exactly.
    await squad.train(2, 3);
    await squad.train(3, 4);
    expect((await runAt(FROZEN + HOUR, squad.id)).told).toEqual([]);
  });

  it('suggests nothing at or under the goal set from next week, and never above 7', async () => {
    const lowered = await squadOf(1);
    for (const week of [1, 2, 3]) await lowered.train(week, 4);
    // The captain already moved next week's goal to 4.
    await sql`insert into public.squad_weekly_goals (squad_id, days_per_member, week_start, set_by)
      values (${lowered.id}, 4, ${monday(4)}, ${lowered.captain.userId})`.execute(db);
    expect((await runAt(FROZEN + HOUR, lowered.id)).told).toEqual([]);

    const keen = await squadOf(1);
    await sql`insert into public.squad_weekly_goals (squad_id, days_per_member, week_start, set_by)
      values (${keen.id}, 6, ${monday(0)}, ${keen.captain.userId})`.execute(db);
    for (const week of [1, 2, 3]) await keen.train(week, 7);
    const { told } = await runAt(FROZEN + HOUR, keen.id);
    expect(told.map((notice) => notice.subject)).toEqual([
      { version: 1, weeks: 3, daysPerMember: 7 },
    ]);
  });

  it('compares with the week after the captain’s own, already Monday in Shanghai', async () => {
    const squad = await squadOf(1);
    for (const week of [1, 2, 3]) await squad.train(week, 5);
    await sql`insert into public.profiles (member_id, time_zone)
      values (${squad.captain.userId}, 'Asia/Shanghai')`.execute(db);
    // An hour after the freeze it is Monday 9am in Shanghai: a change now counts from week 5,
    // where the captain already put 5.
    await sql`insert into public.squad_weekly_goals (squad_id, days_per_member, week_start, set_by)
      values (${squad.id}, 5, ${monday(5)}, ${squad.captain.userId})`.execute(db);
    expect((await runAt(FROZEN + HOUR, squad.id)).told).toEqual([]);
  });

  it('tells a new captain in the same run of weeks, and again after a week under', async () => {
    const squad = await squadOf(2);
    for (const week of [1, 2, 3]) await squad.train(week, 4);
    expect((await runAt(FROZEN + HOUR, squad.id)).told).toHaveLength(1);

    // The captaincy moved; the squad stays over the next week.
    const [, mate] = squad.people;
    await sql`update public.squads set captain_id = ${mate?.userId ?? null}
      where id = ${squad.id}`.execute(db);
    await squad.train(4, 4);
    const handed = await runAt(FROZEN + 7 * DAY + HOUR, squad.id);
    expect(handed.told.map((notice) => notice.member)).toEqual([mate?.userId]);

    // A week under breaks the run; three over after it tell the captain again.
    await squad.train(5, 2);
    for (const week of [6, 7, 8]) await squad.train(week, 5);
    const again = await runAt(FROZEN + 5 * 7 * DAY + HOUR, squad.id);
    expect(again.told.map((notice) => notice.subject)).toEqual([
      { version: 1, weeks: 3, daysPerMember: 5 },
    ]);
  });

  it('keeps no suggestion whose notice failed, so the next run tells the captain', async () => {
    const squad = await squadOf(1);
    for (const week of [1, 2, 3]) await squad.train(week, 5);
    noticesDown = true;
    const failed = await runAt(FROZEN + HOUR, squad.id).finally(() => {
      noticesDown = false;
    });
    expect(failed.run.failed).toBeGreaterThanOrEqual(1);
    expect(await squads.goalSuggestions(SquadId.parse(squad.id))).toEqual([]);
    expect((await runAt(FROZEN + 2 * HOUR, squad.id)).told).toHaveLength(1);
  });

  it('keeps every suggestion, and the log refuses a change', async () => {
    const squad = await squadOf(1);
    for (const week of [1, 2, 3]) await squad.train(week, 5);
    await runAt(FROZEN + HOUR, squad.id);
    expect(await squads.goalSuggestions(SquadId.parse(squad.id))).toEqual([
      { week: monday(3), captain: squad.captain.userId, daysPerMember: 5 },
    ]);
    await expect(
      sql`update public.squad_goal_suggestions set days_per_member = 7
        where squad_id = ${squad.id}`.execute(db),
    ).rejects.toThrow(/append-only/);
    await expect(
      sql`delete from public.squad_goal_suggestions where squad_id = ${squad.id}`.execute(db),
    ).rejects.toThrow(/append-only/);
  });
});
