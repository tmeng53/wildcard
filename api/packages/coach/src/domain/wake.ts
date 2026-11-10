import { NEW_YORK, mondayOf, wallClockAt } from '@wildcard/time-zones';

import type { CoachSettings, SquadId } from './settings.js';
import { saidTo, type SquadWeek } from './squad-week.js';

// When a coach wakes: for each check-in shared to its squad, to learn from it, for each reply a
// member writes to it under a check-in, to answer, once a day for the squad's 战术板 line, and
// once a night before that to tidy its memory (its dream: Tracy, 2026-11-08).
// The daily wake keeps the squad's own clock (小队时区), as its 战报 does; each member's note then
// reaches them on their own clock.

/** Why a coach woke. */
export type WakeReason =
  | { readonly kind: 'checkIn'; readonly checkIn: string }
  | { readonly kind: 'comment'; readonly checkIn: string; readonly comment: string }
  | { readonly kind: 'daily'; readonly day: string }
  /** The night before `day`'s daily wake: the coach rewrites its memory from the day before. */
  | { readonly kind: 'dream'; readonly day: string };

export interface NewWake {
  readonly squad: SquadId;
  readonly reason: WakeReason;
}

export interface Wake extends NewWake {
  readonly id: number;
}

/** From this hour on the squad's clock, its daily wake is due. */
export const DAILY_HOUR = 6;

/** From this hour on the squad's clock, when its day begins, its dream is due. */
export const DREAM_HOUR = 3;

/** How far back a run looks for check-ins to wake for, so a missed run or two loses none. */
export const CHECK_IN_WINDOW_MS = 60 * 60_000;

/**
 * Every week a member's own day can be in at `now`, or was in an hour ago: members' clocks run
 * from UTC−11 to UTC+14, so from 7 hours behind New York to 19 ahead (−10 leaves room to spare).
 * One week most of the time, two near Monday.
 */
export function weeksAround(now: Date): string[] {
  const hours = [-10, 0, 19];
  const weeks = hours.map((hour) =>
    mondayOf(wallClockAt(new Date(now.getTime() + hour * 3_600_000), NEW_YORK).day),
  );
  return [...new Set(weeks)];
}

/**
 * The wakes due for a squad at `now`: one for each check-in made in the last
 * `CHECK_IN_WINDOW_MS`, one for each reply to the coach written in it (each is queued as it is
 * written, too; this catches one that wasn't), the night's dream from `DREAM_HOUR` and the
 * day's own from `DAILY_HOUR` on the squad's clock, `timeZone`. Saving them again is harmless,
 * since a squad has one wake per check-in, one per reply, one dream and one daily wake a day.
 */
export function wakesDue({
  squad,
  week,
  now,
  timeZone,
}: {
  readonly squad: SquadId;
  readonly week: SquadWeek;
  readonly now: Date;
  readonly timeZone: string;
}): NewWake[] {
  const since = now.getTime() - CHECK_IN_WINDOW_MS;
  const wakes: NewWake[] = week.checkIns
    .filter(
      ({ createdAt, unposted }) =>
        unposted !== true && createdAt.getTime() > since && createdAt <= now,
    )
    .map(({ id }) => ({ squad, reason: { kind: 'checkIn', checkIn: id } }));
  for (const checkIn of week.checkIns) {
    for (const comment of checkIn.comments) {
      if (saidTo(comment) === undefined) continue;
      if (comment.at.getTime() <= since || comment.at > now) continue;
      wakes.push({ squad, reason: { kind: 'comment', checkIn: checkIn.id, comment: comment.id } });
    }
  }
  const { day, hour } = wallClockAt(now, timeZone);
  // The dream first, so the daily wake reads the memory it tidied.
  if (hour >= DREAM_HOUR) wakes.push({ squad, reason: { kind: 'dream', day } });
  if (hour >= DAILY_HOUR) wakes.push({ squad, reason: { kind: 'daily', day } });
  return wakes;
}

/** The tokens a wake used, as the model's provider counts them. */
export interface TokenUsage {
  readonly requests: number;
  /** Every input token, cached ones included. */
  readonly inputTokens: number;
  /** Those of the input tokens the provider had cached, at its cheaper price. */
  readonly cachedInputTokens: number;
  readonly outputTokens: number;
}

/** What tokens cost at the settings' prices, in US dollars' millionths, rounded up. */
export function costMicros(
  usage: TokenUsage,
  prices: Pick<
    CoachSettings,
    'inputMicrosPerMillion' | 'cachedInputMicrosPerMillion' | 'outputMicrosPerMillion'
  >,
): number {
  const cached = Math.min(usage.cachedInputTokens, usage.inputTokens);
  return Math.ceil(
    ((usage.inputTokens - cached) * prices.inputMicrosPerMillion +
      cached * prices.cachedInputMicrosPerMillion +
      usage.outputTokens * prices.outputMicrosPerMillion) /
      1_000_000,
  );
}

/** One tool call of a wake's run, as the admins read it back. */
export interface WakeStep {
  readonly tool: string;
  /** The arguments the model called it with. */
  readonly input: unknown;
  /** What the tool answered: in full for a change, only its length for a read. */
  readonly output: string;
}
