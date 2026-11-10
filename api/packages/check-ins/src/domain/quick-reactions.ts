import { z } from 'zod';

import { Emoji } from './reaction.js';

// The reaction bar's quick emoji, in order, kept in the database so they change with no app
// release (Tracy, 2026-11-09). Any one emoji is still a reaction; these are only the ones the
// bar offers first.

export const QuickReactions = z.strictObject({
  version: z.literal(1),
  emoji: z
    .array(Emoji)
    .min(1)
    .max(6)
    .refine((list) => new Set(list).size === list.length, 'Each emoji once'),
});
export type QuickReactions = z.infer<typeof QuickReactions>;
