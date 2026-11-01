import type { CoachSettings, SquadId } from './settings.js';
import type { SquadWeek } from './squad-week.js';

// When a coach wakes: for each check-in shared to its squad, to learn from it, and once a day
// for the squad's 战术板 line. Days are New York's, as the weekly awards' are.

/** Why a coach woke. */
export type WakeReason =
  | { readonly kind: 'checkIn'; readonly checkIn: string }
  | { readonly kind: 'daily'; readonly day: string };

export interface NewWake {
  readonly squad: SquadId;
  readonly reason: WakeReason;
}

export interface Wake extends NewWake {
  readonly id: number;
}

/** From this hour, New York time, a squad's daily wake is due. */
export const DAILY_HOUR = 6;

/** How far back a run looks for check-ins to wake for, so a missed run or two loses none. */
export const CHECK_IN_WINDOW_MS = 60 * 60_000;

/** New York's day (`YYYY-MM-DD`) and hour at `now`. */
export function newYorkTime(now: Date): { readonly day: string; readonly hour: number } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);
  const part = (type: string) => parts.find((each) => each.type === type)?.value ?? '';
  return { day: `${part('year')}-${part('month')}-${part('day')}`, hour: Number(part('hour')) };
}

/** The Monday of a day's week, `YYYY-MM-DD`. */
export function weekStartOf(day: string): string {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() - ((date.getUTCDay() + 6) % 7));
  return date.toISOString().slice(0, 10);
}

/**
 * The wakes due for a squad at `now`: one for each check-in made in the last
 * `CHECK_IN_WINDOW_MS`, and the day's own from `DAILY_HOUR`. Saving them again is harmless,
 * since a squad has one wake per check-in and one a day.
 */
export function wakesDue({
  squad,
  week,
  now,
}: {
  readonly squad: SquadId;
  readonly week: SquadWeek;
  readonly now: Date;
}): NewWake[] {
  const since = now.getTime() - CHECK_IN_WINDOW_MS;
  const wakes: NewWake[] = week.checkIns
    .filter(({ createdAt }) => createdAt.getTime() > since && createdAt <= now)
    .map(({ id }) => ({ squad, reason: { kind: 'checkIn', checkIn: id } }));
  const { day, hour } = newYorkTime(now);
  if (hour >= DAILY_HOUR) wakes.push({ squad, reason: { kind: 'daily', day } });
  return wakes;
}

/** The tokens a wake used, as the model's provider counts them. */
export interface TokenUsage {
  readonly requests: number;
  readonly inputTokens: number;
  readonly outputTokens: number;
}

/** What tokens cost at the settings' prices, in US dollars' millionths, rounded up. */
export function costMicros(
  usage: TokenUsage,
  prices: Pick<CoachSettings, 'inputMicrosPerMillion' | 'outputMicrosPerMillion'>,
): number {
  return Math.ceil(
    (usage.inputTokens * prices.inputMicrosPerMillion +
      usage.outputTokens * prices.outputMicrosPerMillion) /
      1_000_000,
  );
}
