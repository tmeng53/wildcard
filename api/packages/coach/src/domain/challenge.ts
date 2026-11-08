import { z } from 'zod';

// The day's challenge (今日挑战) a coach may set a member on their morning note (Tracy,
// 2026-11-08): one doable thing that makes today better, taken from their plan, 饮食小目标 and
// recent training. A title, and a number with its unit when it has one (「喝水 8 杯」, 「拉伸 10
// 分钟」, or just 「早点睡」). The member accepts it (接受挑战) or lets it go (算了); the coach
// judges how it went from what they post.

/** The longest title, in characters; the database checks the same. */
export const CHALLENGE_TITLE_LIMIT = 8;
/** The longest unit, in characters; the database checks the same. */
export const CHALLENGE_UNIT_LIMIT = 4;
/** The biggest amount; the database checks the same. */
export const CHALLENGE_AMOUNT_MAX = 9999;

export const Challenge = z
  .strictObject({
    title: z.string().trim().min(1).max(CHALLENGE_TITLE_LIMIT),
    amount: z.int().min(1).max(CHALLENGE_AMOUNT_MAX).optional(),
    unit: z.string().trim().min(1).max(CHALLENGE_UNIT_LIMIT).optional(),
  })
  .refine(({ amount, unit }) => (amount === undefined) === (unit === undefined), {
    message: 'amount and unit come together, or neither',
  });
export type Challenge = z.infer<typeof Challenge>;

/** What the member said to it: accepted (接受挑战), declined (算了) or nothing yet. */
export const ChallengeAnswer = z.enum(['accepted', 'declined']);
export type ChallengeAnswer = z.infer<typeof ChallengeAnswer>;

/** A challenge as the model reads it: 「喝水 8 杯」. */
export function challengeText({ title, amount, unit }: Challenge): string {
  return amount === undefined || unit === undefined ? title : `${title} ${String(amount)} ${unit}`;
}

/** The member's challenge today and what they said to it, as a check-in's wake tells the coach. */
export function challengeLine({
  challenge,
  answer,
}: {
  readonly challenge: Challenge;
  readonly answer: ChallengeAnswer | undefined;
}): string {
  const said =
    answer === 'accepted' ? '他接受了' : answer === 'declined' ? '他说算了' : '他还没回应';
  return `你今天给他的挑战：「${challengeText(challenge)}」，${said}。`;
}
