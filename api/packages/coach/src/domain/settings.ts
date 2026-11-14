import { z } from 'zod';

// What every coach runs with, as kept in the database and changed by an admin: so coaching,
// the model and the rules change without a deploy. What its calls cost and may spend is the AI
// usage ledger's, with every other model call's.

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

/**
 * How hard the model thinks before it answers: more reads a member's tone better and costs more
 * output tokens, which the AI usage ledger counts at the model's output price.
 */
export const CoachReasoning = z
  .enum(['none', 'minimal', 'low', 'medium', 'high'])
  .describe(
    'How hard the model thinks before answering: none, minimal, low, medium or high. Thinking is billed as output tokens.',
  );
export type CoachReasoning = z.infer<typeof CoachReasoning>;

const fields = {
  coaching: z
    .boolean()
    .describe(
      'Whether coaches wake at all. On, every squad that hired a coach has one; off, none does and nothing is sent.',
    ),
  model: CoachModel,
  reasoning: CoachReasoning,
  // The night's dream rewrites the squad's memory, which every later wake goes on, so it may
  // run on a stronger model, thinking harder, than the day's wakes (Tracy, 2026-11-12).
  dreamModel: CoachModel.describe(
    'The model of the night’s dream, which rewrites the squad’s memory: openai/model. It needs a price in the AI usage settings, like model.',
  ),
  dreamReasoning: CoachReasoning.describe(
    'How hard the dream’s model thinks: none, minimal, low, medium or high. Thinking is billed as output tokens.',
  ),
  rules: z
    .string()
    .min(1)
    .max(20_000)
    .describe('The rules every coach follows, Chinese; each coach’s soul comes after them.'),
  wakes: z
    .string()
    .min(1)
    .max(20_000)
    .describe(
      'How each kind of wake goes (a check-in, a reply or @ to the coach, a new day) and how the coach keeps its memory, Chinese; after each coach’s soul. `{replyLimit}` and `{noteLimit}` stand for the longest reply and the longest 战术板 line or 便条 in Chinese (English has its own, longer limits, which each tool states), which the API puts in.',
    ),
  replyRules: z
    .string()
    .min(1)
    .max(20_000)
    .describe(
      'How the coach answers a post or a comment written to it, Chinese: the instructions of a reply, after the coach’s soul. Only a reply reads them, never the shared rules or wakes.',
    ),
  noteRules: z
    .string()
    .min(1)
    .max(20_000)
    .describe(
      'How the coach writes its morning, the 战术板 line and each member’s 便条, Chinese: the instructions of the daily wake’s notes, after the coach’s soul. Only the morning’s notes read them, never the shared rules or wakes.',
    ),
  challengeModel: CoachModel.describe(
    'The model that sets each member’s day challenge on the daily wake, before the coach writes its notes in its own voice (openai/model). Without a price in the AI usage settings, the coach’s own model sets them.',
  ),
  challengeRules: z
    .string()
    .min(1)
    .max(20_000)
    .describe(
      'What makes a good day challenge, Chinese: the whole instructions of the run that sets them (never the shared rules).',
    ),
  noteHour: z
    .int()
    .min(0)
    .max(23)
    .describe(
      'The hour on each member’s own clock when the coach’s morning note (便条) reaches them: pushed silently and told in 通知. A note written after it reaches them at once.',
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

/** The model a wake runs on and how hard it thinks: the dream's own, else the day's. */
export function modelOf(
  settings: Pick<CoachSettings, 'model' | 'reasoning' | 'dreamModel' | 'dreamReasoning'>,
  kind: string,
): { readonly model: CoachModel; readonly reasoning: CoachReasoning } {
  return kind === 'dream'
    ? { model: settings.dreamModel, reasoning: settings.dreamReasoning }
    : { model: settings.model, reasoning: settings.reasoning };
}
