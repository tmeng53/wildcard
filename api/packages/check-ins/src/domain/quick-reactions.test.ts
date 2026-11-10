import { describe, expect, it } from 'vitest';

import { QuickReactions } from './quick-reactions.js';

describe('the quick reactions', () => {
  it('takes one to six different emoji', () => {
    expect(QuickReactions.safeParse({ version: 1, emoji: ['❤️', '💪'] }).success).toBe(true);
    expect(QuickReactions.safeParse({ version: 1, emoji: [] }).success).toBe(false);
    expect(QuickReactions.safeParse({ version: 1, emoji: Array(7).fill('🔥') }).success).toBe(
      false,
    );
    expect(QuickReactions.safeParse({ version: 1, emoji: ['🔥', '🔥'] }).success).toBe(false);
    expect(QuickReactions.safeParse({ version: 1, emoji: ['ok'] }).success).toBe(false);
  });
});
