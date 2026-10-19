import { describe, expect, it } from 'vitest';

import { createMemoryRateLimit } from './memory-rate-limit.js';

function clockAt(start: string) {
  let now = new Date(start);
  return {
    clock: () => now,
    advance: (seconds: number) => {
      now = new Date(now.getTime() + seconds * 1000);
    },
  };
}

describe('a rate limit kept in memory', () => {
  it('allows the limit in a window, then says when to come back', () => {
    const time = clockAt('2026-10-19T12:00:00Z');
    const take = createMemoryRateLimit({ limit: 3, windowSeconds: 60, clock: time.clock });
    expect([take('a'), take('a'), take('a')]).toStrictEqual([
      { allowed: true },
      { allowed: true },
      { allowed: true },
    ]);
    time.advance(20.5);
    expect(take('a')).toStrictEqual({ allowed: false, retryAfterSeconds: 40 });
    expect(take('b')).toStrictEqual({ allowed: true });
    time.advance(39.5);
    expect(take('a')).toStrictEqual({ allowed: true });
  });

  it('forgets ended windows when it holds too many keys, and starts over when none ended', () => {
    const time = clockAt('2026-10-19T12:00:00Z');
    const take = createMemoryRateLimit({
      limit: 1,
      windowSeconds: 60,
      clock: time.clock,
      maxKeys: 2,
    });
    take('a');
    time.advance(61);
    take('b');
    // 'a' has ended, so it goes and 'b' keeps its count.
    take('c');
    expect(take('b')).toStrictEqual({ allowed: false, retryAfterSeconds: 60 });
    // 'b' and 'c' are both running: everything is forgotten to make room.
    take('d');
    expect(take('b')).toStrictEqual({ allowed: true });
  });
});
