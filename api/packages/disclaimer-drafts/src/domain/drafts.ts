import { z } from 'zod';

import { graphemeCount } from '@wildcard/typed-text';

// What the model answers, and the shape every answer has before a member sees it. An answer
// out of shape is never shown in part: the app shows its dice suggestions instead (spec A5,
// A8). What the drafts may say is the prompt's job, not a check's.

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

/** True when `draft` fits the swipe card: its length in bounds, on one line. */
function fitsCard(draft: string): boolean {
  const length = graphemeCount(draft);
  return length >= DRAFT_MIN && length <= DRAFT_MAX && !/[\r\n\u0085\u2028\u2029]/u.test(draft);
}

/**
 * What a reply comes to, or `undefined` when it is out of shape: not exactly three distinct
 * drafts, or a draft that doesn't fit the card.
 */
export function outcomeOf(reply: ModelReply): DraftsOutcome | undefined {
  switch (reply.outcome) {
    case 'selfHarm':
      return { kind: 'care' };
    case 'unsafe':
      return { kind: 'declined' };
    case 'drafts': {
      const [first, second, third, ...rest] = reply.drafts.map((draft) => draft.trim());
      if (first === undefined || second === undefined || third === undefined) return undefined;
      if (rest.length > 0 || new Set([first, second, third]).size < 3) return undefined;
      if (![first, second, third].every(fitsCard)) return undefined;
      return { kind: 'drafts', drafts: [first, second, third] };
    }
  }
}
