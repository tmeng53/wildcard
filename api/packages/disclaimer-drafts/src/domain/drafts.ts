import { z } from 'zod';

import { graphemeCount } from '@wildcard/typed-text';

import type { DraftReason } from './draft-request.js';

// What the model answers, and the checks every answer passes before a member sees it. An
// answer that fails a check is never shown in part: the app shows its dice suggestions
// instead (spec A5, A8).

/** The model's reply, held to this shape by structured output. */
export const ModelReply = z.strictObject({
  version: z.literal(1),
  outcome: z.enum(['drafts', 'selfHarm', 'unsafe']),
  drafts: z.array(z.string()),
});
export type ModelReply = z.infer<typeof ModelReply>;

/** What a request for drafts comes to. */
export type DraftsOutcome =
  /** Three drafts to swipe through. */
  | { readonly kind: 'drafts'; readonly drafts: readonly [string, string, string] }
  /** The reason speaks of self-harm: no drafts, and only its author sees the care line. */
  | { readonly kind: 'care' }
  /** The reason is one the AI doesn't write about: the app shows its dice suggestions. */
  | { readonly kind: 'declined' };

const DRAFT_MIN = 15;
const DRAFT_MAX = 80;

/**
 * Words a draft never holds: no body metrics, calories or macros in v1. Matched case-blind, so
 * a draft that trips one falls back to the dice rather than reaching a member.
 */
const BODY_WORDS = [
  '体重',
  '胖',
  '瘦',
  '身材',
  '体脂',
  '减肥',
  '减脂',
  '公斤',
  '卡路里',
  '热量',
  '大卡',
  '蛋白质',
  '碳水',
  '脂肪',
  'bmi',
  'calorie',
  'kcal',
  'macros',
];

/** Reasons this short may be echoed: a keyword is fine, the whole sentence isn't. */
const ECHO_MIN = 4;

/** True when `draft` is one a member may be shown for `reason`. */
function isShowable(draft: string, reason: DraftReason): boolean {
  const length = graphemeCount(draft);
  return (
    length >= DRAFT_MIN &&
    length <= DRAFT_MAX &&
    !/[\r\n\u2028\u2029]/u.test(draft) &&
    !/\p{Extended_Pictographic}/u.test(draft) &&
    !BODY_WORDS.some((word) => draft.toLowerCase().includes(word)) &&
    !(graphemeCount(reason) >= ECHO_MIN && draft.includes(reason))
  );
}

/**
 * What a reply comes to for `reason`, or `undefined` when it fails a check: not exactly three
 * distinct drafts, or a draft out of bounds.
 */
export function outcomeOf(reply: ModelReply, reason: DraftReason): DraftsOutcome | undefined {
  switch (reply.outcome) {
    case 'selfHarm':
      return { kind: 'care' };
    case 'unsafe':
      return { kind: 'declined' };
    case 'drafts': {
      const [first, second, third, ...rest] = reply.drafts.map((draft) => draft.trim());
      if (first === undefined || second === undefined || third === undefined) return undefined;
      if (rest.length > 0 || new Set([first, second, third]).size < 3) return undefined;
      if (![first, second, third].every((draft) => isShowable(draft, reason))) return undefined;
      return { kind: 'drafts', drafts: [first, second, third] };
    }
  }
}
