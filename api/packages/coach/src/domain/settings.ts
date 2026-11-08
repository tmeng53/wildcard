import { z } from 'zod';

// What every coach runs with, as kept in the database and changed by an admin: so coaching,
// the model, the rules and the prices change without a deploy.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A squad's id, lower-cased as Postgres stores a uuid. */
export const SquadId = z
  .uuid()
  .transform((id) => id.toLowerCase())
  .brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/**
 * The coach's model, as `openai/model`. The coach runs on the OpenAI Agents SDK, so it is an
 * OpenAI model; the database checks the same.
 */
export const CoachModel = z
  .string()
  .regex(/^openai\/[A-Za-z0-9._:-]{1,100}$/)
  .brand<'CoachModel'>()
  .describe('openai/model, such as openai/gpt-6-luna.');
export type CoachModel = z.infer<typeof CoachModel>;

/**
 * One day on the coach's holiday calendar: `MM-DD` every year, or `YYYY-MM-DD` that year only
 * (a holiday that moves, such as 春节), and its name, which the coach is told as it is.
 */
export const CoachHoliday = z.strictObject({
  date: z
    .string()
    .regex(/^(\d{4}-)?(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/)
    // A day that exists: in its year, or in some year for MM-DD (02-29 only in leap years).
    .refine((date) => {
      const full = date.length === 5 ? `2000-${date}` : date;
      const at = Date.parse(`${full}T00:00:00Z`);
      return !Number.isNaN(at) && new Date(at).toISOString().slice(0, 10) === full;
    }, 'a day that exists')
    .describe('MM-DD for every year, or YYYY-MM-DD for that year only; New York’s day.'),
  name: z
    .string()
    .trim()
    .min(1)
    .max(40)
    .regex(/^[^\r\n]*$/)
    .describe('The day’s name, such as 感恩节, told to the coach as a plain fact.'),
});
export type CoachHoliday = z.infer<typeof CoachHoliday>;

/** The names of the holidays on `day` (`YYYY-MM-DD`, New York), in the calendar's order. */
export function holidaysOn(calendar: readonly CoachHoliday[], day: string): string[] {
  return calendar
    .filter(({ date }) => date === day || date === day.slice(5))
    .map(({ name }) => name);
}

/** US dollars in millionths, per million tokens. */
const MicrosPerMillion = z.int().min(0).max(2_000_000_000);

const fields = {
  coaching: z
    .boolean()
    .describe(
      'Whether coaches wake at all. On, every squad that hired a coach has one; off, none does and nothing is sent.',
    ),
  model: CoachModel,
  rules: z
    .string()
    .min(1)
    .max(20_000)
    .describe('The rules every coach follows, Chinese; each coach’s soul comes after them.'),
  inputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for input tokens: US dollars in millionths per million tokens.',
  ),
  cachedInputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for input tokens the provider had cached from an earlier request with the same beginning: US dollars in millionths per million tokens.',
  ),
  outputMicrosPerMillion: MicrosPerMillion.describe(
    'The model’s price for output tokens: US dollars in millionths per million tokens.',
  ),
  noteHour: z
    .int()
    .min(0)
    .max(23)
    .describe(
      'The hour on each member’s own clock when the coach’s morning note (便条) reaches them: pushed silently and told in 通知. A note written after it reaches them at once.',
    ),
  squadDailyCapMicros: z
    .int()
    .min(0)
    .max(2_000_000_000)
    .describe(
      'What one squad’s coach may spend a day, on the squad’s own clock: US dollars in millionths. Once the squad’s spending that day reaches it, its coach is off duty: its wakes are skipped until the next day.',
    ),
  dailyCapMicros: z
    .int()
    .min(0)
    .max(2_000_000_000)
    .describe(
      'What every squad’s coach together may spend a day, New York’s day: US dollars in millionths. Once reached, every coach is off duty until the next day.',
    ),
  holidays: z
    .array(CoachHoliday)
    .max(500)
    .describe(
      'The holiday calendar: on each of these days (New York) every wake’s task tells the coach the day’s name, and nothing about what to say. A change replaces the whole list.',
    ),
};

/** The settings, whole, as stored and logged. */
export const CoachSettings = z.strictObject({ version: z.literal(1), ...fields });
export type CoachSettings = z.infer<typeof CoachSettings>;

/** What an admin changes: any of the settings, the rest staying as they are. */
export const CoachSettingsChange = z.strictObject(fields).partial();
export type CoachSettingsChange = z.infer<typeof CoachSettingsChange>;
