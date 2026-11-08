import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely } from 'kysely';
import { z } from 'zod';

import {
  ChallengeAnswer,
  ChallengeDoneBy,
  type Challenge,
  type ChallengeCompletion,
} from '../domain/challenge.js';
import { cardKey, CoachCardKind } from '../domain/cards.js';
import { CoachId } from '../domain/coach.js';
import { CoachEmoji } from '../domain/reply.js';
import { memberOfPath } from '../domain/memory.js';
import { SquadId } from '../domain/settings.js';
import { CoachFileMemberNotFoundError, CoachSquadNotFoundError } from '../errors.js';
import type { NewWake, Wake } from '../domain/wake.js';
import type {
  CoachActivityStore,
  CoachNoteDeliveryStore,
  CoachReportStore,
  CoachStores,
  CoachTransaction,
  DayChallenge,
  UsageTotal,
} from '../ports.js';
import { letterWhere } from './postgres-coach-letters.js';
import type { DB } from './tables.js';

/** How long a claimed wake may run before another run takes it back. */
const STALE_MINUTES = 15;

/** How old a waiting wake may be and still run; older ones are left. */
const FRESH_HOURS = 24;

/** How long a wake whose try failed waits before its next. */
const RETRY_MINUTES = 5;

/** Postgres's code for a duplicate row: here, a second running wake of a squad. */
const UNIQUE_VIOLATION = '23505';

/** A claimed wake's row as the coach reads it. */
function wakeOf(row: {
  readonly id: string;
  readonly squad_id: string;
  readonly reason: string;
  readonly check_in_id: string | null;
  readonly comment_id: string | null;
  readonly day: string | null;
}): Wake {
  const squad = SquadId.parse(row.squad_id);
  const id = Number(row.id);
  if ((row.reason === 'daily' || row.reason === 'dream') && row.day !== null) {
    return { id, squad, reason: { kind: row.reason, day: row.day } };
  }
  if (row.reason === 'comment' && row.comment_id !== null && row.check_in_id !== null) {
    return {
      id,
      squad,
      reason: { kind: 'comment', checkIn: row.check_in_id, comment: row.comment_id },
    };
  }
  // The database keeps a check-in wake's check-in.
  return { id, squad, reason: { kind: 'checkIn', checkIn: row.check_in_id ?? '' } };
}

/** Queues one wake unless the squad has it; answers the new row, if any. */
function insertWake(
  db: Kysely<DB>,
  { squad, reason, now }: NewWake & { readonly now: Date },
): Promise<readonly { readonly id: string }[]> {
  const insert = db.insertInto('coach_wakes');
  switch (reason.kind) {
    case 'checkIn':
      return insert
        .values({
          squad_id: squad,
          reason: 'checkIn',
          check_in_id: reason.checkIn,
          created_at: now,
        })
        .onConflict((conflict) =>
          conflict.columns(['squad_id', 'check_in_id']).where('reason', '=', 'checkIn').doNothing(),
        )
        .returning('id')
        .execute();
    case 'comment':
      // Nothing when the reply is gone already.
      return sql<{ id: string }>`
        insert into public.coach_wakes (squad_id, reason, check_in_id, comment_id, created_at)
        select ${squad}, 'comment', check_in_id, id, ${now}
        from public.check_in_comments where id = ${reason.comment} and check_in_id = ${reason.checkIn}
        on conflict (squad_id, comment_id) where reason = 'comment' do nothing
        returning id`
        .execute(db)
        .then(({ rows }) => rows);
    case 'daily':
    case 'dream':
      return insert
        .values({ squad_id: squad, reason: reason.kind, day: reason.day, created_at: now })
        .onConflict((conflict) =>
          conflict.columns(['squad_id', 'day']).where('reason', '=', reason.kind).doNothing(),
        )
        .returning('id')
        .execute();
  }
}

/** The coach's wakes, files, notes and usage on Postgres (`supabase/migrations`). */
export function createPostgresCoachStores(db: Kysely<DB>): CoachStores {
  return {
    wakes: {
      async enqueue(wakes, now) {
        let added = 0;
        for (const { squad, reason } of wakes) {
          const inserted = await insertWake(db, { squad, reason, now });
          added += inserted.length;
        }
        return added;
      },

      async claim({ squads, limit, now }) {
        if (squads.length === 0) return [];
        const stale = new Date(now.getTime() - STALE_MINUTES * 60_000);
        const fresh = new Date(now.getTime() - FRESH_HOURS * 3_600_000);
        const retry = new Date(now.getTime() - RETRY_MINUTES * 60_000);
        // A run that stopped on its last try leaves nothing to take back: it failed.
        await db
          .updateTable('coach_wakes')
          .set({ state: 'failed', last_error: 'the run stopped before it ended' })
          .where('state', '=', 'running')
          .where('claimed_at', '<', stale)
          .where('tries', '>=', 3)
          .execute();
        // Which wake can run: one a run must have dropped, or one waiting long enough.
        const claimable = (prefix: '' | 'wake.') =>
          sql<boolean>`${sql.ref(`${prefix}tries`)} < 3 and (
            (${sql.ref(`${prefix}state`)} = 'running' and ${sql.ref(`${prefix}claimed_at`)} < ${stale})
            or (${sql.ref(`${prefix}state`)} = 'waiting' and ${sql.ref(`${prefix}created_at`)} > ${fresh}
              and (${sql.ref(`${prefix}claimed_at`)} is null or ${sql.ref(`${prefix}claimed_at`)} < ${retry})))`;
        // Each squad's next wake: one a run dropped first, then a reply's, else its oldest
        // waiting one; never a squad whose wake is running.
        const next = await db
          .selectFrom('coach_wakes as wake')
          .distinctOn('wake.squad_id')
          .select(['wake.id', 'wake.squad_id', 'wake.created_at'])
          .where('wake.squad_id', 'in', squads)
          .where(claimable('wake.'))
          .where((where) =>
            where.not(
              where.exists(
                where
                  .selectFrom('coach_wakes as running')
                  .select('running.id')
                  .whereRef('running.squad_id', '=', 'wake.squad_id')
                  .where('running.state', '=', 'running')
                  .where('running.claimed_at', '>=', stale),
              ),
            ),
          )
          .orderBy('wake.squad_id')
          .orderBy(sql`wake.state = 'running'`, 'desc')
          // A member's reply waits on its answer, so it goes before older wakes.
          .orderBy(sql`wake.reason = 'comment'`, 'desc')
          .orderBy('wake.created_at')
          .orderBy('wake.id')
          .execute();
        const picked = next
          .toSorted((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
          .slice(0, limit);
        const claimed: Wake[] = [];
        for (const { id } of picked) {
          // Claimed only if it still can be: another run may have taken it, or another of its
          // squad's wakes, which the one-running-a-squad index refuses.
          const row = await db
            .updateTable('coach_wakes')
            .set((eb) => ({ state: 'running', tries: eb('tries', '+', 1), claimed_at: now }))
            .where('id', '=', id)
            .where(claimable(''))
            .returning([
              'id',
              'squad_id',
              'reason',
              'check_in_id',
              'comment_id',
              sql<string | null>`to_char(day, 'YYYY-MM-DD')`.as('day'),
            ])
            .executeTakeFirst()
            .catch((error: unknown) => {
              if (hasErrorCode(error, UNIQUE_VIOLATION)) return undefined;
              throw error;
            });
          if (row !== undefined) claimed.push(wakeOf(row));
        }
        return claimed;
      },

      async finish(wake) {
        await db
          .updateTable('coach_wakes')
          .set({ state: 'done', last_error: null })
          .where('id', '=', String(wake))
          .execute();
      },

      async fail(wake, error) {
        await db
          .updateTable('coach_wakes')
          .set((eb) => ({
            state: eb.case().when('tries', '>=', 3).then('failed').else('waiting').end(),
            last_error: error.slice(0, 1000),
          }))
          .where('id', '=', String(wake))
          .execute();
      },

      async skip(wake, why) {
        await db
          .updateTable('coach_wakes')
          .set({ state: 'skipped', last_error: why.slice(0, 1000) })
          .where('id', '=', String(wake))
          .execute();
      },
    },

    memory: {
      async files(squad) {
        const rows = await db
          .selectFrom('coach_files')
          .distinctOn('path')
          .select(['path', 'body'])
          .where('squad_id', '=', squad)
          .orderBy('path')
          .orderBy('id', 'desc')
          .execute();
        return new Map(rows.map(({ path, body }) => [path, body]));
      },

      async save({ squad, wake, files }) {
        if (files.length === 0) return;
        await saveFiles(db, { squad, wake, files });
      },
    },
    notes: {
      async save({ squad, coach, day, text, wake }) {
        const saved = await db
          .insertInto('coach_notes')
          .values({ squad_id: squad, coach_id: coach, day, text, wake_id: String(wake) })
          .onConflict((conflict) => conflict.columns(['squad_id', 'day']).doNothing())
          .returning('id')
          .execute();
        return saved.length > 0;
      },

      async recent(squad, limit) {
        return db
          .selectFrom('coach_notes')
          .select([sql<string>`to_char(day, 'YYYY-MM-DD')`.as('day'), 'text'])
          .where('squad_id', '=', squad)
          .orderBy('coach_notes.day', 'desc')
          .limit(limit)
          .execute();
      },
    },

    memberNotes: {
      async save({ squad, member, coach, day, text, challenge, wake }) {
        // Nothing when the member left the squad or deleted their account while the run thought.
        const saved = await sql<{ id: string }>`
          insert into public.coach_member_notes
            (squad_id, member_id, coach_id, day, text, challenge_title, challenge_amount,
             challenge_unit, challenge_line, wake_id)
          select ${squad}::uuid, ${member}::uuid, ${coach}, ${day}::date, ${text},
            ${challenge?.title ?? null}, ${challenge?.amount ?? null}::int,
            ${challenge?.unit ?? null}, ${challenge?.line ?? null}, ${String(wake)}::bigint
          where exists (select 1 from auth.users where id = ${member}::uuid)
          on conflict (squad_id, member_id, day) do nothing
          returning id`.execute(db);
        return saved.rows.length > 0;
      },

      challengeOf: (input) => dayChallenge(db, input),

      async complete({ note, by, day }) {
        // Only a challenge, on its own day, not let go, and only the first time: the member may
        // have said 算了 while the run thought.
        const done = await sql`
          insert into public.coach_challenge_completions (note_id, by)
          select m.id, ${by} from public.coach_member_notes m
          where m.id = ${String(note)}::bigint and m.challenge_title is not null
            and m.day = ${day}::date
            and not exists (
              select 1 from public.coach_challenge_answers a
              where a.note_id = m.id and a.answer = 'declined'
            )
          on conflict (note_id) do nothing
          returning note_id`.execute(db);
        return done.rows.length > 0;
      },

      async challengesOn({ squad, day }) {
        const rows = await dayChallenges(db, { squad, day }).execute();
        return rows.flatMap((row) => {
          const challenge = dayChallengeOfRow(row, day);
          return challenge === undefined ? [] : [{ ...challenge, member: row.member_id }];
        });
      },
    },

    replies: {
      async save({ squad, checkIn, coach, text, emoji, mentions = [], wake }) {
        // Nothing when the check-in went while the run was thinking: a failed insert would undo
        // the rest of the wake's save with it.
        const saved = await sql<{ id: string }>`
          insert into public.coach_replies (squad_id, check_in_id, coach_id, text, emoji, wake_id)
          select ${squad}, id, ${coach}, ${text ?? null}, ${emoji ?? null}, ${String(wake)}
          from public.check_ins where id = ${checkIn}
          on conflict (squad_id, check_in_id) do nothing
          returning id`.execute(db);
        const [row] = saved.rows;
        if (row === undefined) return false;
        if (mentions.length > 0)
          await sql`
          insert into public.coach_reply_mentions (reply_id, member_id, position)
          ${mentionRows(row.id, mentions)}`.execute(db);
        return true;
      },

      async find(squad, checkIn) {
        const row = await db
          .selectFrom('coach_replies')
          .select(['coach_id', 'text'])
          .where('squad_id', '=', squad)
          .where('check_in_id', '=', checkIn)
          .executeTakeFirst();
        return row === undefined
          ? undefined
          : { coach: CoachId.parse(row.coach_id), text: row.text ?? undefined };
      },

      async recent(squad, limit) {
        const rows = await db
          .selectFrom('coach_replies')
          .select('emoji')
          .where('squad_id', '=', squad)
          .where('emoji', 'is not', null)
          .orderBy('id', 'desc')
          .limit(limit)
          .execute();
        return rows.flatMap(({ emoji }) => {
          const parsed = CoachEmoji.safeParse(emoji);
          return parsed.success ? [parsed.data] : [];
        });
      },
    },

    answers: {
      async save({ squad, checkIn, comment, coach, text, mentions = [], wake }) {
        // Nothing when the reply went while the run was thinking, as for a reply to a check-in.
        const saved = await sql<{ id: string }>`
          insert into public.coach_answers (squad_id, check_in_id, comment_id, coach_id, text, wake_id)
          select ${squad}, check_in_id, id, ${coach}, ${text}, ${String(wake)}
          from public.check_in_comments where id = ${comment} and check_in_id = ${checkIn}
          on conflict (squad_id, comment_id) do nothing
          returning id`.execute(db);
        const [row] = saved.rows;
        if (row === undefined) return false;
        if (mentions.length > 0)
          await sql`
          insert into public.coach_answer_mentions (answer_id, member_id, position)
          ${mentionRows(row.id, mentions)}`.execute(db);
        return true;
      },

      async ofCheckIn(squad, checkIn) {
        const rows = await db
          .selectFrom('coach_answers')
          .select(['comment_id', 'text', 'at'])
          .where('squad_id', '=', squad)
          .where('check_in_id', '=', checkIn)
          .orderBy('at')
          .orderBy('id')
          .execute();
        return rows.map((row) => ({
          comment: row.comment_id,
          text: row.text,
          at: new Date(row.at),
        }));
      },
    },

    usage: {
      async record({ squad, wake, coach, model, usage, costMicros, at }) {
        await db
          .insertInto('coach_usage')
          .values({
            squad_id: squad,
            // Null for a letter, which has no wake, and when the wake has gone meanwhile (its
            // check-in was deleted).
            wake_id: (eb) =>
              wake === undefined
                ? sql<string | null>`null`
                : eb.selectFrom('coach_wakes').select('id').where('id', '=', String(wake)),
            coach_id: coach,
            model,
            requests: usage.requests,
            input_tokens: usage.inputTokens,
            cached_input_tokens: usage.cachedInputTokens,
            output_tokens: usage.outputTokens,
            cost_micros: costMicros,
            at,
          })
          .execute();
      },

      async spent({ squad, since }) {
        const row = await db
          .selectFrom('coach_usage')
          .select((eb) =>
            eb.fn.coalesce(eb.fn.sum<string>('cost_micros'), sql<string>`0`).as('spent'),
          )
          .where('at', '>=', since)
          .$if(squad !== undefined, (query) => query.where('squad_id', '=', squad ?? ''))
          .executeTakeFirstOrThrow();
        return Number(row.spent);
      },
    },

    steps: {
      async record({ squad, wake, steps }) {
        if (steps.length === 0) return;
        // Nothing when the wake has gone meanwhile (its check-in or comment was deleted).
        await sql`
          insert into public.coach_wake_steps (squad_id, wake_id, step, tool, input, output)
          select ${squad}, wake.id, step.n, step.tool, step.input, step.output
          from public.coach_wakes wake,
            jsonb_to_recordset(${JSON.stringify(
              steps.map(({ tool, input, output }, index) => ({
                n: index + 1,
                tool: tool.slice(0, 40),
                input: input ?? null,
                output: output.slice(0, 2000),
              })),
            )}::jsonb) as step (n integer, tool text, input jsonb, output text)
          where wake.id = ${String(wake)}`.execute(db);
      },
    },
  };
}

/** What a squad's coaches have said, read from Postgres for its members. */
export function createPostgresCoachActivity(db: Kysely<DB>): CoachActivityStore {
  return {
    letter: (squad) => letterWhere(db, { toCoachNowOf: squad }),

    async latestNote(squad) {
      const row = await db
        .selectFrom('coach_notes')
        .innerJoin('coaches', 'coaches.id', 'coach_notes.coach_id')
        .select([
          sql<string>`to_char(coach_notes.day, 'YYYY-MM-DD')`.as('day'),
          'coach_notes.text',
          'coach_notes.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
        ])
        .where('coach_notes.squad_id', '=', squad)
        .orderBy('coach_notes.day', 'desc')
        .limit(1)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      return {
        day: row.day,
        text: row.text,
        coach: { id: row.coach_id, name: row.name, look: row.look },
        at: new Date(row.at),
      };
    },

    async memberNote({ squad, member, since }) {
      const row = await db
        .selectFrom('coach_member_notes')
        .innerJoin('coaches', 'coaches.id', 'coach_member_notes.coach_id')
        // Only from the coach the squad has now: a fired coach's notes stop.
        .innerJoin('squad_coaches', (join) =>
          join
            .onRef('squad_coaches.squad_id', '=', 'coach_member_notes.squad_id')
            .onRef('squad_coaches.coach_id', '=', 'coach_member_notes.coach_id'),
        )
        // Only once it reached the member, at the morning hour on their clock.
        .innerJoin(
          'coach_member_note_deliveries',
          'coach_member_note_deliveries.note_id',
          'coach_member_notes.id',
        )
        .leftJoin(
          'coach_challenge_answers',
          'coach_challenge_answers.note_id',
          'coach_member_notes.id',
        )
        .select([
          'coach_member_notes.id',
          sql<string>`to_char(coach_member_notes.day, 'YYYY-MM-DD')`.as('day'),
          'coach_member_notes.text',
          'coach_member_notes.challenge_title',
          'coach_member_notes.challenge_amount',
          'coach_member_notes.challenge_unit',
          'coach_member_notes.challenge_line',
          'coach_challenge_answers.answer',
          'coach_member_notes.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
        ])
        .where('coach_member_notes.squad_id', '=', squad)
        .where('coach_member_notes.member_id', '=', member)
        .where('coach_member_note_deliveries.at', '>=', since)
        .where((eb) =>
          eb.not(
            eb.exists(
              eb
                .selectFrom('coach_member_note_reads')
                .select('coach_member_note_reads.note_id')
                .whereRef('coach_member_note_reads.note_id', '=', 'coach_member_notes.id'),
            ),
          ),
        )
        .orderBy('coach_member_notes.id', 'desc')
        .limit(1)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      const challenge = challengeOfRow(row);
      return {
        id: Number(row.id),
        day: row.day,
        text: row.text,
        ...(challenge === undefined ? {} : { challenge }),
        ...(row.answer === null ? {} : { challengeAnswer: ChallengeAnswer.parse(row.answer) }),
        coach: { id: row.coach_id, name: row.name, look: row.look },
        at: new Date(row.at),
      };
    },

    async answerChallenge({ squad, member, note, answer, reason }) {
      // Only a note that reached the member: one still waiting isn't theirs to answer yet.
      const mine = await db
        .selectFrom('coach_member_notes')
        .innerJoin(
          'coach_member_note_deliveries',
          'coach_member_note_deliveries.note_id',
          'coach_member_notes.id',
        )
        .select(['coach_member_notes.challenge_title'])
        .where('coach_member_notes.id', '=', String(note))
        .where('coach_member_notes.squad_id', '=', squad)
        .where('coach_member_notes.member_id', '=', member)
        .executeTakeFirst();
      if (mine === undefined) return 'noNote';
      if (mine.challenge_title === null) return 'noChallenge';
      // The first answer stands; a second is the first's.
      await sql`
        insert into public.coach_challenge_answers (note_id, answer, reason)
        values (${String(note)}::bigint, ${answer}, ${answer === 'declined' ? (reason ?? null) : null})
        on conflict (note_id) do nothing`.execute(db);
      const kept = await db
        .selectFrom('coach_challenge_answers')
        .select(['answer', 'reason'])
        .where('note_id', '=', String(note))
        .executeTakeFirstOrThrow();
      return {
        answer: ChallengeAnswer.parse(kept.answer),
        ...(kept.reason === null ? {} : { reason: kept.reason }),
      };
    },

    challengeOf: (input) => dayChallenge(db, input),

    async completeChallenge({ squad, member, note, today }) {
      // Only a note that reached the member, as with answering it.
      const mine = await db
        .selectFrom('coach_member_notes')
        .innerJoin(
          'coach_member_note_deliveries',
          'coach_member_note_deliveries.note_id',
          'coach_member_notes.id',
        )
        .leftJoin(
          'coach_challenge_answers',
          'coach_challenge_answers.note_id',
          'coach_member_notes.id',
        )
        .select([
          'coach_member_notes.challenge_title',
          sql<string>`to_char(coach_member_notes.day, 'YYYY-MM-DD')`.as('day'),
          'coach_challenge_answers.answer',
        ])
        .where('coach_member_notes.id', '=', String(note))
        .where('coach_member_notes.squad_id', '=', squad)
        .where('coach_member_notes.member_id', '=', member)
        .executeTakeFirst();
      if (mine === undefined) return 'noNote';
      if (mine.challenge_title === null) return 'noChallenge';
      const done = await completionOf(db, note);
      // The first one stands, whoever marked it, even once the day is over.
      if (done !== undefined) return done;
      if (mine.answer === 'declined') return 'declined';
      if (mine.day !== today) return 'dayOver';
      await sql`
        insert into public.coach_challenge_completions (note_id, by)
        values (${String(note)}::bigint, 'member')
        on conflict (note_id) do nothing`.execute(db);
      // The database keeps no completion after a 算了 that won a race with this one.
      return (await completionOf(db, note)) ?? 'declined';
    },

    async putAway({ squad, member, note }) {
      // Only the member's own note in that squad; a second time is the first's.
      await sql`
        insert into public.coach_member_note_reads (note_id)
        select id from public.coach_member_notes
        where id = ${String(note)}::bigint and squad_id = ${squad}::uuid and member_id = ${member}::uuid
        on conflict (note_id) do nothing`.execute(db);
      const mine = await db
        .selectFrom('coach_member_notes')
        .select('id')
        .where('id', '=', String(note))
        .where('squad_id', '=', squad)
        .where('member_id', '=', member)
        .executeTakeFirst();
      return mine !== undefined;
    },

    async cards({ squad, member, since }) {
      // Each kind from its own table, for this member in this squad: the squad's 战术板 lines,
      // the member's notes (and their challenges) once delivered, the coach's lines to the
      // member's check-ins, and its answers to the member's replies.
      const rows = await sql<{
        kind: 'board' | 'note' | 'challenge' | 'challengeDone' | 'reply' | 'answer';
        id: string;
        day: string | null;
        text: string | null;
        check_in_id: string | null;
        comment_id: string | null;
        challenge_title: string | null;
        challenge_amount: number | null;
        challenge_unit: string | null;
        challenge_line: string | null;
        answer: string | null;
        reason: string | null;
        done_by: string | null;
        done_at: Date | null;
        at: Date;
        coach_id: string;
        name: string;
        look: string;
      }>`
        with mine as (
          select 'board' as kind, to_char(n.day, 'YYYY-MM-DD') as id,
            to_char(n.day, 'YYYY-MM-DD') as day, n.text, null::uuid as check_in_id,
            null::uuid as comment_id, null as challenge_title, null::int as challenge_amount,
            null as challenge_unit, null as challenge_line, null as answer, null as reason,
            null as done_by,
            null::timestamptz as done_at, n.at, n.coach_id
          from public.coach_notes n
          where n.squad_id = ${squad}::uuid and n.at >= ${since}
          union all
          select 'note', m.id::text, to_char(m.day, 'YYYY-MM-DD'), m.text, null, null, null,
            null, null, null, null, null, null, null, d.at, m.coach_id
          from public.coach_member_notes m
          join public.coach_member_note_deliveries d on d.note_id = m.id
          where m.squad_id = ${squad}::uuid and m.member_id = ${member}::uuid and d.at >= ${since}
          union all
          select 'challenge', m.id::text, to_char(m.day, 'YYYY-MM-DD'), null, null, null,
            m.challenge_title, m.challenge_amount, m.challenge_unit, m.challenge_line, a.answer,
            a.reason, done.by, done.at, d.at, m.coach_id
          from public.coach_member_notes m
          join public.coach_member_note_deliveries d on d.note_id = m.id
          left join public.coach_challenge_answers a on a.note_id = m.id
          left join public.coach_challenge_completions done on done.note_id = m.id
          where m.squad_id = ${squad}::uuid and m.member_id = ${member}::uuid
            and m.challenge_title is not null and d.at >= ${since}
          union all
          select 'challengeDone', m.id::text, to_char(m.day, 'YYYY-MM-DD'), null, null, null,
            m.challenge_title, m.challenge_amount, m.challenge_unit, m.challenge_line, null, null,
            done.by, done.at, done.at, m.coach_id
          from public.coach_member_notes m
          join public.coach_member_note_deliveries d on d.note_id = m.id
          join public.coach_challenge_completions done on done.note_id = m.id
          where m.squad_id = ${squad}::uuid and m.member_id = ${member}::uuid
            and done.by = 'coach' and done.at >= ${since}
          union all
          select 'reply', r.id::text, null, r.text, r.check_in_id, null, null, null, null, null,
            null, null, null, null, r.at, r.coach_id
          from public.coach_replies r
          join public.check_ins c on c.id = r.check_in_id
          where r.squad_id = ${squad}::uuid and c.member_id = ${member}::uuid
            and r.text is not null and r.at >= ${since}
          union all
          select 'answer', a.id::text, null, a.text, a.check_in_id, a.comment_id, null, null,
            null, null, null, null, null, null, a.at, a.coach_id
          from public.coach_answers a
          join public.check_in_comments cc on cc.id = a.comment_id
          where a.squad_id = ${squad}::uuid and cc.member_id = ${member}::uuid and a.at >= ${since}
        )
        select mine.*, coaches.name, coaches.look
        from mine join public.coaches on coaches.id = mine.coach_id
        order by mine.at,
          array_position(array['board', 'note', 'challenge', 'challengeDone', 'reply', 'answer'], mine.kind),
          mine.id`.execute(db);
      return rows.rows.map((row) => {
        const base = {
          id: row.id,
          coach: { id: row.coach_id, name: row.name, look: row.look },
          at: new Date(row.at),
        };
        switch (row.kind) {
          case 'board':
          case 'note':
            return { ...base, kind: row.kind, day: row.day ?? '', text: row.text ?? '' };
          case 'challenge':
            return {
              ...base,
              kind: row.kind,
              day: row.day ?? '',
              challenge: challengeOfRow(row) ?? { title: '' },
              answer: row.answer === null ? undefined : ChallengeAnswer.parse(row.answer),
              reason: row.reason ?? undefined,
              completion: completionOfRow(row),
            };
          case 'challengeDone':
            return {
              ...base,
              kind: row.kind,
              day: row.day ?? '',
              challenge: challengeOfRow(row) ?? { title: '' },
            };
          case 'reply':
            return {
              ...base,
              kind: row.kind,
              checkIn: row.check_in_id ?? '',
              text: row.text ?? '',
            };
          case 'answer':
            return {
              ...base,
              kind: row.kind,
              checkIn: row.check_in_id ?? '',
              comment: row.comment_id ?? '',
              text: row.text ?? '',
            };
        }
      });
    },

    async seenCards({ squad, member }) {
      const rows = await db
        .selectFrom('coach_card_seen')
        .select(['kind', 'card_id'])
        .where('squad_id', '=', squad)
        .where('member_id', '=', member)
        .execute();
      return new Set(rows.map((row) => cardKey(CoachCardKind.parse(row.kind), row.card_id)));
    },

    async markSeen({ squad, member, kind, id }) {
      await sql`
        insert into public.coach_card_seen (member_id, squad_id, kind, card_id)
        values (${member}::uuid, ${squad}::uuid, ${kind}, ${id})
        on conflict do nothing`.execute(db);
    },

    async replies(squad, checkIns) {
      if (checkIns.length === 0) return [];
      const rows = await db
        .selectFrom('coach_replies')
        .innerJoin('coaches', 'coaches.id', 'coach_replies.coach_id')
        .select([
          'coach_replies.check_in_id',
          'coach_replies.text',
          'coach_replies.emoji',
          'coach_replies.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
          mentionsOf('reply'),
        ])
        .where('coach_replies.squad_id', '=', squad)
        .where('coach_replies.check_in_id', 'in', checkIns)
        .execute();
      return rows.map((row) => ({
        checkIn: row.check_in_id,
        coach: { id: row.coach_id, name: row.name, look: row.look },
        text: row.text ?? undefined,
        emoji: row.emoji ?? undefined,
        mentions: row.mentions,
        at: new Date(row.at),
      }));
    },

    async answers(squad, checkIns) {
      if (checkIns.length === 0) return [];
      const rows = await db
        .selectFrom('coach_answers')
        .innerJoin('coaches', 'coaches.id', 'coach_answers.coach_id')
        .select([
          'coach_answers.check_in_id',
          'coach_answers.comment_id',
          'coach_answers.text',
          'coach_answers.at',
          'coaches.id as coach_id',
          'coaches.name',
          'coaches.look',
          mentionsOf('answer'),
        ])
        .where('coach_answers.squad_id', '=', squad)
        .where('coach_answers.check_in_id', 'in', checkIns)
        .orderBy('coach_answers.at')
        .orderBy('coach_answers.id')
        .execute();
      return rows.map((row) => ({
        checkIn: row.check_in_id,
        comment: row.comment_id,
        coach: { id: row.coach_id, name: row.name, look: row.look },
        text: row.text,
        mentions: row.mentions,
        at: new Date(row.at),
      }));
    },
  };
}

/** Runs work on the coach's stores in one Postgres transaction. */
/** The morning notes still to deliver, and marking them delivered, on Postgres. */
export function createPostgresCoachNoteDelivery(db: Kysely<DB>): CoachNoteDeliveryStore {
  return {
    async undelivered(since) {
      const rows = await db
        .selectFrom('coach_member_notes')
        .innerJoin('coaches', 'coaches.id', 'coach_member_notes.coach_id')
        // Only from the coach the squad has now: a fired coach's notes stop.
        .innerJoin('squad_coaches', (join) =>
          join
            .onRef('squad_coaches.squad_id', '=', 'coach_member_notes.squad_id')
            .onRef('squad_coaches.coach_id', '=', 'coach_member_notes.coach_id'),
        )
        .leftJoin(
          'coach_member_note_deliveries',
          'coach_member_note_deliveries.note_id',
          'coach_member_notes.id',
        )
        .select([
          'coach_member_notes.id',
          'coach_member_notes.squad_id',
          'coach_member_notes.member_id',
          'coach_member_notes.coach_id',
          sql<string>`to_char(coach_member_notes.day, 'YYYY-MM-DD')`.as('day'),
          'coach_member_notes.text',
          'coach_member_notes.at',
          'coaches.name',
        ])
        .where('coach_member_notes.at', '>=', since)
        .where('coach_member_note_deliveries.note_id', 'is', null)
        .orderBy('coach_member_notes.id')
        .execute();
      return rows.map((row) => ({
        id: Number(row.id),
        squad: SquadId.parse(row.squad_id),
        member: row.member_id,
        coach: CoachId.parse(row.coach_id),
        day: row.day,
        text: row.text,
        at: new Date(row.at),
        coachName: row.name,
      }));
    },

    async delivered(note) {
      const saved = await db
        .insertInto('coach_member_note_deliveries')
        .values({ note_id: String(note) })
        .onConflict((conflict) => conflict.column('note_id').doNothing())
        .returning('note_id')
        .execute();
      return saved.length > 0;
    },
  };
}

export function postgresCoachTransaction(db: Kysely<DB>): CoachTransaction {
  return (work) => db.transaction().execute((trx) => work(createPostgresCoachStores(trx)));
}

/** What a squad's coach has done, read from Postgres for the admins. */
export function createPostgresCoachReport(db: Kysely<DB>): CoachReportStore {
  return {
    async squad(squad, now) {
      const files = await db
        .selectFrom('coach_files')
        .distinctOn('path')
        .select(['path', 'body', 'at'])
        .where('squad_id', '=', squad)
        .orderBy('path')
        .orderBy('id', 'desc')
        .execute();
      const notes = await db
        .selectFrom('coach_notes')
        .select([sql<string>`to_char(day, 'YYYY-MM-DD')`.as('day'), 'text'])
        .where('squad_id', '=', squad)
        .orderBy('coach_notes.day', 'desc')
        .limit(14)
        .execute();
      const wakes = await db
        .selectFrom('coach_wakes')
        .select(['id', 'reason', 'state', 'tries', 'last_error', 'created_at'])
        .where('squad_id', '=', squad)
        .orderBy('id', 'desc')
        .limit(20)
        .execute();
      const steps =
        wakes.length === 0
          ? []
          : await db
              .selectFrom('coach_wake_steps')
              .select(['wake_id', 'tool', 'input', 'output'])
              .where(
                'wake_id',
                'in',
                wakes.map(({ id }) => id),
              )
              .orderBy('id')
              .execute();
      const weekAgo = new Date(now.getTime() - 7 * 86_400_000);
      const totalSince = async (since: Date | undefined): Promise<UsageTotal> => {
        const row = await db
          .selectFrom('coach_usage')
          .select((eb) => [
            eb.fn.countAll<string>().as('wakes'),
            sql<string>`coalesce(sum(requests), 0)`.as('requests'),
            sql<string>`coalesce(sum(input_tokens), 0)`.as('input_tokens'),
            sql<string>`coalesce(sum(cached_input_tokens), 0)`.as('cached_input_tokens'),
            sql<string>`coalesce(sum(output_tokens), 0)`.as('output_tokens'),
            sql<string>`coalesce(sum(cost_micros), 0)`.as('cost_micros'),
          ])
          .where('squad_id', '=', squad)
          .$if(since !== undefined, (query) => query.where('at', '>=', since ?? now))
          .executeTakeFirstOrThrow();
        return {
          wakes: Number(row.wakes),
          requests: Number(row.requests),
          inputTokens: Number(row.input_tokens),
          cachedInputTokens: Number(row.cached_input_tokens),
          outputTokens: Number(row.output_tokens),
          costMicros: Number(row.cost_micros),
        };
      };
      const hired = await db
        .selectFrom('squad_coaches')
        .select('coach_id')
        .where('squad_id', '=', squad)
        .executeTakeFirst();
      return {
        version: 1,
        coach: hired === undefined ? null : CoachId.parse(hired.coach_id),
        files: files.map(({ path, body, at }) => ({ path, body, at: new Date(at) })),
        notes,
        wakes: wakes.map((wake) => ({
          reason:
            wake.reason === 'daily' || wake.reason === 'comment' || wake.reason === 'dream'
              ? wake.reason
              : 'checkIn',
          state: wake.state,
          tries: wake.tries,
          lastError: wake.last_error,
          createdAt: new Date(wake.created_at),
          steps: steps
            .filter(({ wake_id }) => wake_id === wake.id)
            .map(({ tool, input, output }) => ({ tool, input, output })),
        })),
        usage: { total: await totalSince(undefined), lastWeek: await totalSince(weekAgo) },
      };
    },
  };
}

/**
 * Saves new versions of a squad's files. A squad or member page's member that doesn't exist (an
 * admin's typo) is told by name.
 */
async function saveFiles(
  db: Kysely<DB>,
  {
    squad,
    wake,
    files,
  }: {
    readonly squad: string;
    readonly wake: number | undefined;
    readonly files: readonly { readonly path: string; readonly body: string }[];
  },
): Promise<void> {
  try {
    await db
      .insertInto('coach_files')
      .values(
        files.map(({ path, body }) => ({
          squad_id: squad,
          path,
          member_id: memberOfPath(path) ?? null,
          body,
          // Null for an admin's edit, or when the wake has gone meanwhile (its check-in was
          // deleted).
          wake_id:
            wake === undefined
              ? null
              : db.selectFrom('coach_wakes').select('id').where('id', '=', String(wake)),
        })),
      )
      .execute();
  } catch (error) {
    if (hasErrorCode(error, FOREIGN_KEY_VIOLATION)) {
      const constraint = z.object({ constraint: z.string() }).safeParse(error).data?.constraint;
      if (constraint === 'coach_files_squad_id_fkey') throw new CoachSquadNotFoundError();
      if (constraint === 'coach_files_member_id_fkey') throw new CoachFileMemberNotFoundError();
    }
    throw error;
  }
}

const FOREIGN_KEY_VIOLATION = '23503';

/** Whom a coach's line (a reply to a check-in or an answer) @s, in the order written, as a column. */
function mentionsOf(line: 'reply' | 'answer') {
  const [table, of] =
    line === 'reply'
      ? [sql.table('public.coach_reply_mentions'), sql.ref('reply_id')]
      : [sql.table('public.coach_answer_mentions'), sql.ref('answer_id')];
  const id = sql.ref(line === 'reply' ? 'coach_replies.id' : 'coach_answers.id');
  return sql<string[]>`coalesce(
    (select array_agg(member_id::text order by position) from ${table} where ${of} = ${id}),
    '{}'::text[])`.as('mentions');
}

/**
 * The rows of a coach's line's @s, in the order written, for an insert: an account deleted while
 * the run was thinking is left out, as a failed insert would undo the rest of the wake's save.
 */
function mentionRows(line: string, mentions: readonly string[]) {
  return sql`
    select ${line}::bigint, m.member, m.position - 1
    from unnest(${[...mentions]}::uuid[]) with ordinality as m (member, position)
    where exists (select 1 from auth.users where id = m.member)`;
}

/** A note row's challenge, if it set one. */
function challengeOfRow(row: {
  readonly challenge_title: string | null;
  readonly challenge_amount: number | null;
  readonly challenge_unit: string | null;
  readonly challenge_line: string | null;
}): Challenge | undefined {
  if (row.challenge_title === null) return undefined;
  return {
    title: row.challenge_title,
    ...(row.challenge_amount === null || row.challenge_unit === null
      ? {}
      : { amount: row.challenge_amount, unit: row.challenge_unit }),
    ...(row.challenge_line === null ? {} : { line: row.challenge_line }),
  };
}

/** A completion row, if the challenge was marked done. */
function completionOfRow(row: {
  readonly done_by: string | null;
  readonly done_at: Date | string | null;
}): ChallengeCompletion | undefined {
  if (row.done_by === null || row.done_at === null) return undefined;
  return { by: ChallengeDoneBy.parse(row.done_by), at: new Date(row.done_at) };
}

/** Who marked a note's challenge done and when, if anyone did. */
async function completionOf(db: Kysely<DB>, note: number) {
  const row = await db
    .selectFrom('coach_challenge_completions')
    .select(['by as done_by', 'at as done_at'])
    .where('note_id', '=', String(note))
    .executeTakeFirst();
  return row === undefined ? undefined : completionOfRow(row);
}

/** The squad's notes of a day that reached their members, with their challenges' answers. */
function dayChallenges(
  db: Kysely<DB>,
  { squad, day }: { readonly squad: SquadId; readonly day: string },
) {
  return db
    .selectFrom('coach_member_notes')
    .innerJoin(
      'coach_member_note_deliveries',
      'coach_member_note_deliveries.note_id',
      'coach_member_notes.id',
    )
    .leftJoin('coach_challenge_answers', 'coach_challenge_answers.note_id', 'coach_member_notes.id')
    .leftJoin(
      'coach_challenge_completions',
      'coach_challenge_completions.note_id',
      'coach_member_notes.id',
    )
    .select([
      'coach_member_notes.id',
      'coach_member_notes.member_id',
      'coach_member_notes.challenge_title',
      'coach_member_notes.challenge_amount',
      'coach_member_notes.challenge_unit',
      'coach_member_notes.challenge_line',
      'coach_challenge_answers.answer',
      'coach_challenge_answers.reason',
      'coach_challenge_completions.by as done_by',
      'coach_challenge_completions.at as done_at',
    ])
    .where('coach_member_notes.squad_id', '=', squad)
    .where('coach_member_notes.day', '=', day)
    .orderBy('coach_member_notes.id');
}

/** A note row's challenge as its member and coach read it, if it set one. */
function dayChallengeOfRow(
  row: Parameters<typeof challengeOfRow>[0] &
    Parameters<typeof completionOfRow>[0] & {
      readonly id: string;
      readonly answer: string | null;
      readonly reason: string | null;
    },
  day: string,
): DayChallenge | undefined {
  const challenge = challengeOfRow(row);
  if (challenge === undefined) return undefined;
  return {
    note: Number(row.id),
    day,
    challenge,
    answer: row.answer === null ? undefined : ChallengeAnswer.parse(row.answer),
    reason: row.reason ?? undefined,
    completion: completionOfRow(row),
  };
}

/**
 * The member's challenge on their note of `day`, once the note reached them (before then they
 * can't have seen it), with their answer and whether it is done.
 */
async function dayChallenge(
  db: Kysely<DB>,
  {
    squad,
    member,
    day,
  }: { readonly squad: SquadId; readonly member: string; readonly day: string },
): Promise<DayChallenge | undefined> {
  const row = await dayChallenges(db, { squad, day })
    .where('coach_member_notes.member_id', '=', member)
    .executeTakeFirst();
  return row === undefined ? undefined : dayChallengeOfRow(row, day);
}
