import { describe, expect, it } from 'vitest';

import { checkCheckInTime } from './check-in-time.js';

const now = new Date('2026-10-18T12:00:00.000Z');
const at = (iso: string) => new Date(iso);

/** The reason a check for a member in `timeZone` (none: no profile) would refuse with, or 'ok'. */
const verdictIn = (timeZone: string | undefined) => (createdAt: string, day: string) => {
  try {
    checkCheckInTime({ createdAt: at(createdAt), day }, { now, timeZone });
    return 'ok';
  } catch (error) {
    return error instanceof Error && 'reason' in error ? String(error.reason) : 'thrown';
  }
};
const verdict = verdictIn(undefined);

describe('checkCheckInTime', () => {
  it('takes a check-in made up to 48 hours ago', () => {
    expect(verdict('2026-10-16T12:00:00.000Z', '2026-10-16')).toBe('ok');
    expect(verdict('2026-10-16T11:59:59.999Z', '2026-10-16')).toBe('CHECK_IN_TOO_OLD');
  });

  it('takes a phone clock up to 5 minutes ahead', () => {
    expect(verdict('2026-10-18T12:05:00.000Z', '2026-10-18')).toBe('ok');
    expect(verdict('2026-10-18T12:05:00.001Z', '2026-10-18')).toBe('CHECK_IN_IN_THE_FUTURE');
  });

  it('without a time zone, takes a day within one day of the moment’s UTC date', () => {
    // 4am UTC on the 18th is still the 17th in Los Angeles, and already the 18th in Tokyo.
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-17')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-19')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-16')).toBe('CHECK_IN_DAY_MISMATCH');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-20')).toBe('CHECK_IN_DAY_MISMATCH');
  });

  it('with a time zone, takes their day at that moment or the day before, never the day after', () => {
    // 11:31 UTC on the 18th is 00:31 on the 18th in Pago Pago (UTC-11): the 17th by the 3am rule.
    const pagoPago = 'Pacific/Pago_Pago';
    expect(verdictIn(pagoPago)('2026-10-18T11:31:00.000Z', '2026-10-17')).toBe('ok');
    expect(verdictIn(pagoPago)('2026-10-18T11:31:00.000Z', '2026-10-16')).toBe('ok');
    expect(verdictIn(pagoPago)('2026-10-18T11:31:00.000Z', '2026-10-18')).toBe(
      'CHECK_IN_DAY_MISMATCH',
    );
    expect(verdictIn(pagoPago)('2026-10-18T11:31:00.000Z', '2026-10-15')).toBe(
      'CHECK_IN_DAY_MISMATCH',
    );
    // The same moment is 19:31 on the 18th in Shanghai.
    expect(verdictIn('Asia/Shanghai')('2026-10-18T11:31:00.000Z', '2026-10-18')).toBe('ok');
    expect(verdictIn('Asia/Shanghai')('2026-10-18T11:31:00.000Z', '2026-10-19')).toBe(
      'CHECK_IN_DAY_MISMATCH',
    );
  });
});
