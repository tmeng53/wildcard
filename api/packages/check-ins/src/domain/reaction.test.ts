import { describe, expect, it } from 'vitest';

import { Emoji } from './reaction.js';

describe('Emoji', () => {
  it('takes any one emoji', () => {
    for (const emoji of ['❤️', '💪', '😂', '1️⃣', '🇨🇦', '👍🏽', '👨‍👩‍👧', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', '😵‍💫']) {
      expect(Emoji.safeParse(emoji).success).toBe(true);
    }
  });

  it('refuses text, two emoji and a digit or # on its own', () => {
    for (const text of [
      '',
      '1',
      '#',
      'a',
      '加油',
      '❤️❤️',
      '😂 ',
      ' ',
      '❤',
      `❤️${'\u{FE0F}'.repeat(20)}`,
    ]) {
      expect(Emoji.safeParse(text).success).toBe(false);
    }
  });
});
