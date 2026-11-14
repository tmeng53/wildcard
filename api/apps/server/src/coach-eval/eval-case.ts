import { Challenge, ChallengeAnswer, ChallengeDoneBy, Coach, CoachSettings } from '@wildcard/coach';
import { ModelPrice } from '@wildcard/ai-usage';
import { ReaderLanguage } from '@wildcard/language-model';
import { z } from 'zod';

// The coach's offline eval (Tracy, 2026-11-14): a case is one moment of a squad, as the coach's
// wake reads it (the week, the memory files, what the coach said before, the day's challenge),
// the wake that comes then, and what a good run does there. Cases hold members' words, so they
// live outside this repository (the private feedback repository); only their shape is here.

const Moment = z.iso.datetime({ offset: true }).transform((at) => new Date(at));

const Comment = z.strictObject({
  id: z.string().min(1),
  member: z.string().min(1),
  text: z.string(),
  at: Moment,
  toCoach: z.string().optional(),
  mentionsCoach: z.string().optional(),
  replyTo: z.string().optional(),
  mentions: z.array(z.string()).optional(),
});

const CheckIn = z.strictObject({
  id: z.string().min(1),
  member: z.string().min(1),
  day: z.iso.date(),
  postedDay: z.iso.date().optional(),
  createdAt: Moment,
  postedTime: z
    .string()
    .regex(/^\d\d:\d\d$/)
    .optional(),
  trainedTime: z
    .strictObject({
      from: z.string().regex(/^\d\d:\d\d$/),
      to: z
        .string()
        .regex(/^\d\d:\d\d$/)
        .optional(),
      day: z.iso.date().optional(),
      source: z.enum(['health', 'typed']),
    })
    .optional(),
  kind: z.enum(['trained', 'healthyMeal', 'cheatMeal', 'disclaimer']),
  sport: z.string().optional(),
  minutes: z.int().optional(),
  text: z.string().optional(),
  place: z.string().optional(),
  restDay: z.literal(true).optional(),
  photos: z.array(z.string()).optional(),
  reactedBy: z.array(z.string()).default([]),
  comments: z.array(Comment).default([]),
  unposted: z.literal(true).optional(),
});

/** A squad's week as the coach's wake reads it (`SquadWeek`), with times as ISO strings. */
export const EvalWeek = z.strictObject({
  weekStart: z.iso.date(),
  name: z.string().optional(),
  members: z.array(
    z.strictObject({
      member: z.string().min(1),
      nickname: z.string().optional(),
      language: ReaderLanguage.optional(),
    }),
  ),
  language: ReaderLanguage.optional(),
  checkIns: z.array(CheckIn),
});
export type EvalWeek = z.infer<typeof EvalWeek>;

/** What a good run does, checked on each trial's outcome. */
export const Expectation = z.discriminatedUnion('kind', [
  /** The run called `tool` (`called: true`) or never did. */
  z.strictObject({
    kind: z.literal('tool'),
    tool: z.string().min(1),
    called: z.boolean(),
    why: z.string().optional(),
  }),
  /** The run said a line members read: a reply to the check-in or an answer to the comment. */
  z.strictObject({ kind: z.literal('says'), why: z.string().optional() }),
  /** No line members read holds any of these words. */
  z.strictObject({
    kind: z.literal('avoids'),
    words: z.array(z.string().min(1)).min(1),
    why: z.string().optional(),
  }),
  /** Every line members read is written in this language. */
  z.strictObject({
    kind: z.literal('language'),
    language: ReaderLanguage,
    why: z.string().optional(),
  }),
  /**
   * A judge model reads the case's context and the run's lines and says whether this holds:
   * one yes-or-no criterion, written so a stranger could tell.
   */
  z.strictObject({
    kind: z.literal('judge'),
    criterion: z.string().min(1),
    why: z.string().optional(),
  }),
]);
export type Expectation = z.infer<typeof Expectation>;

export const EvalCase = z.strictObject({
  version: z.literal(1),
  /** The file's name without `.json`. */
  id: z.string().regex(/^[a-z0-9][a-z0-9-]*$/),
  /** What it checks, in a line. */
  title: z.string().min(1),
  /** The incident it came from: where and when it went wrong. */
  source: z.string().optional(),
  /** The coach at work, by id. */
  coach: z.string().min(1),
  /** When the wake runs. */
  now: Moment,
  /** The squad's clock (小队时区). */
  timeZone: z.string().min(1),
  week: EvalWeek,
  /** Weeks before `week`, the one before it first, as `squad_week` and the post tools read them. */
  pastWeeks: z.array(EvalWeek).default([]),
  /** The squad's memory files by stored path (`people/<member id>.md`, `coaches/<coach id>.md`). */
  files: z.record(z.string(), z.string()).default({}),
  /** What coaches said to check-ins before the wake. */
  replies: z
    .array(
      z.strictObject({
        checkIn: z.string(),
        coach: z.string().optional(),
        text: z.string().optional(),
        emoji: z.string().optional(),
        at: Moment.optional(),
      }),
    )
    .default([]),
  /** What coaches answered members' replies before the wake. */
  answers: z
    .array(
      z.strictObject({
        checkIn: z.string(),
        comment: z.string(),
        coach: z.string().optional(),
        text: z.string(),
        at: Moment,
      }),
    )
    .default([]),
  /** The day's challenges on members' morning notes, and how each went so far. */
  challenges: z
    .array(
      z.strictObject({
        member: z.string(),
        day: z.iso.date(),
        challenge: Challenge,
        answer: ChallengeAnswer.optional(),
        reason: z.string().optional(),
        completion: z.strictObject({ by: ChallengeDoneBy, at: Moment }).optional(),
      }),
    )
    .default([]),
  /** The change of coach that brought this one, with the letter left, if any. */
  handover: z
    .strictObject({ from: z.string(), at: Moment, letter: z.string().optional() })
    .optional(),
  /**
   * Each member's plan this week, Monday first: a sport's name, `练` for any, or `休息`; read by
   * the day's challenges.
   */
  plans: z.record(z.string(), z.array(z.string().min(1)).length(7)).default({}),
  /**
   * The wake: a check-in just posted, a comment to the coach, or the morning's run that sets the
   * day's challenges (only that run: the notes after it are not written).
   */
  wake: z.discriminatedUnion('kind', [
    z.strictObject({ kind: z.literal('checkIn'), checkIn: z.string() }),
    z.strictObject({ kind: z.literal('comment'), checkIn: z.string(), comment: z.string() }),
    z.strictObject({ kind: z.literal('challenges') }),
  ]),
  expect: z.array(Expectation).min(1),
});
export type EvalCase = z.infer<typeof EvalCase>;

/**
 * The squad as it was when the wake ran: the check-ins, comments, coach's words and challenge
 * completions after `now` left out, so cases taken from one moment of a squad (`moment` in a
 * case file) each see only what was there at their own time.
 */
export function asOf(testCase: EvalCase): EvalCase {
  const by = (at: Date | undefined) => at === undefined || at <= testCase.now;
  const week = (each: EvalWeek): EvalWeek => ({
    ...each,
    checkIns: each.checkIns
      .filter(({ createdAt }) => by(createdAt))
      .map((checkIn) => ({ ...checkIn, comments: checkIn.comments.filter(({ at }) => by(at)) })),
  });
  return {
    ...testCase,
    week: week(testCase.week),
    pastWeeks: testCase.pastWeeks.map(week),
    replies: testCase.replies.filter(({ at }) => by(at)),
    answers: testCase.answers.filter(({ at }) => by(at)),
    challenges: testCase.challenges.map(({ completion, ...challenge }) => ({
      ...challenge,
      ...(completion !== undefined && by(completion.at) ? { completion } : {}),
    })),
  };
}

/**
 * What the coach runs with in the eval: the live settings, every coach and the models' prices,
 * as the admin tools show them (`get_coach_settings`, `list_coaches`, `get_ai_usage_settings`).
 */
export const EvalSettings = z.strictObject({
  version: z.literal(1),
  /** When they were taken from the live database. */
  takenAt: z.iso.datetime({ offset: true }).optional(),
  coach: CoachSettings,
  coaches: z.array(Coach),
  prices: z.record(z.string(), ModelPrice),
});
export type EvalSettings = z.infer<typeof EvalSettings>;
