import { describe, expect, it } from 'vitest';

import { MemeNotFoundError } from './errors.js';

// Every error the memes module throws, so a changed reason or status shows up as a diff.
describe('meme errors', () => {
  it('each has its reason and status', () => {
    const { name, reason, status } = new MemeNotFoundError('city不city');
    expect([name, reason, status]).toStrictEqual([
      'MemeNotFoundError',
      'MEME_NOT_FOUND',
      'NOT_FOUND',
    ]);
  });
});
