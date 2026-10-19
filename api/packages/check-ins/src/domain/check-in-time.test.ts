import { describe, expect, it } from 'vitest';

import { checkCheckInTime } from './check-in-time.js';

const now = new Date('2026-10-18T12:00:00.000Z');
const at = (iso: string) => new Date(iso);

/** The reason a check would refuse with, or 'ok'. */
function verdict(createdAt: string, day: string): string {
  try {
    checkCheckInTime({ createdAt: at(createdAt), day }, now);
    return 'ok';
  } catch (error) {
    return error instanceof Error && 'reason' in error ? String(error.reason) : 'thrown';
  }
}

describe('checkCheckInTime', () => {
  it('takes a check-in made up to 48 hours ago', () => {
    expect(verdict('2026-10-16T12:00:00.000Z', '2026-10-16')).toBe('ok');
    expect(verdict('2026-10-16T11:59:59.999Z', '2026-10-16')).toBe('CHECK_IN_TOO_OLD');
  });

  it('takes a phone clock up to 5 minutes ahead', () => {
    expect(verdict('2026-10-18T12:05:00.000Z', '2026-10-18')).toBe('ok');
    expect(verdict('2026-10-18T12:05:00.001Z', '2026-10-18')).toBe('CHECK_IN_IN_THE_FUTURE');
  });

  it('takes a day within one day of the moment’s UTC date', () => {
    // 4am UTC on the 18th is still the 17th in Los Angeles, and already the 18th in Tokyo.
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-17')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-19')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-16')).toBe('CHECK_IN_DAY_MISMATCH');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-20')).toBe('CHECK_IN_DAY_MISMATCH');
  });
});
