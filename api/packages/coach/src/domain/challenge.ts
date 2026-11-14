import { typedText } from '@wildcard/typed-text';
import { z } from 'zod';

import { longestLine } from './line-limits.js';

// The day's challenge (今日挑战) a coach may set a member on their morning note (Tracy,
// 2026-11-08): one doable thing that makes today better, taken from their plan, 饮食小目标 and
// recent training. A title, and a number with its unit when it has one (「喝水 8 杯」, 「拉伸 10
// 分钟」, 「早睡 1 小时」). The member accepts it (接受挑战) or lets it go (算了), and it is
// done once the member says so (我完成了) or the coach sees it in that day's check-ins, only on
// its own day; the first one stands.

/** The biggest amount; the database checks the same. */
export const CHALLENGE_AMOUNT_MAX = 9999;

/**
 * A challenge as it is kept, each of its words up to its longest in any language, as the
 * database holds them; the coach's tool holds each to its own language's limit (`LINE_LIMITS`).
 */
export const Challenge = z
  .strictObject({
    title: z.string().trim().min(1).max(longestLine('challengeTitle')),
    amount: z.int().min(1).max(CHALLENGE_AMOUNT_MAX).optional(),
    unit: z.string().trim().min(1).max(longestLine('challengeUnit')).optional(),
    /** The coach talking to the member under the title, about why (「昨天跑完腿还紧，睡前拉一拉。」). */
    line: z.string().trim().min(1).max(longestLine('challengeLine')).optional(),
  })
  .refine(({ amount, unit }) => (amount === undefined) === (unit === undefined), {
    message: 'amount and unit come together, or neither',
  });
export type Challenge = z.infer<typeof Challenge>;

/** What the member said to it: accepted (接受挑战), declined (算了) or nothing yet. */
export const ChallengeAnswer = z.enum(['accepted', 'declined']);
export type ChallengeAnswer = z.infer<typeof ChallengeAnswer>;

/** The longest reason for letting a challenge go, in characters. */
export const DECLINE_REASON_LIMIT = 60;

/** Why the member let a challenge go (算了), if they said: 「我鸡蛋过敏」. */
export const DeclineReason = typedText({
  max: DECLINE_REASON_LIMIT,
  oneLine: true,
  description: 'Why they let it go, if they say; only with `declined`. Their coach remembers it.',
});

/** Who marked a challenge done: the member (我完成了) or the coach, from their check-ins. */
export const ChallengeDoneBy = z.enum(['member', 'coach']);
export type ChallengeDoneBy = z.infer<typeof ChallengeDoneBy>;

/** A challenge marked done: by whom and when. */
export interface ChallengeCompletion {
  readonly by: ChallengeDoneBy;
  readonly at: Date;
}

/** A challenge as the model reads it: 「喝水 8 杯」. */
export function challengeText({ title, amount, unit }: Challenge): string {
  return amount === undefined || unit === undefined ? title : `${title} ${String(amount)} ${unit}`;
}

/**
 * The challenge the member took up today, as a check-in's wake tells the coach; one they let go or
 * never answered is never told there.
 */
export function challengeSection({
  challenge,
  completion,
}: {
  readonly challenge: Challenge;
  readonly completion?: ChallengeCompletion | undefined;
}): string {
  const said =
    completion?.by === 'member'
      ? '说已经完成了'
      : completion?.by === 'coach'
        ? '完成了（你记的）'
        : '接受了';
  return ['## 你今天给他的挑战', `- 挑战：${challengeText(challenge)}`, `- 他：${said}`].join('\n');
}

/** A note that reached its member, with how its challenge went if it set one. */
export interface DeliveredNote {
  readonly member: string;
  /** The squad's day it was for, `YYYY-MM-DD`. */
  readonly day: string;
  readonly text: string;
  readonly challenge?: {
    readonly challenge: Challenge;
    readonly answer: ChallengeAnswer | undefined;
    /** Why they let it go, if they said. */
    readonly reason: string | undefined;
    readonly completion: ChallengeCompletion | undefined;
  };
}
