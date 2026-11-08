import { describe, expect, it } from 'vitest';

import { checkCheckInTime } from './check-in-time.js';

const now = new Date('2026-10-18T12:00:00.000Z');
const at = (iso: string) => new Date(iso);

/** The reason a check for a member in `timeZone` (none: no profile) would refuse with, or 'ok'. */
const verdictIn = (timeZone: string | undefined) => (createdAt: string, day: string) => {
  try {
    const posted = checkCheckInTime({ createdAt: at(createdAt), day }, { now, timeZone });
    return posted === day ? 'ok' : `ok, posted ${posted}`;
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

  it('without a time zone, posts on the day it counts for within one day of the UTC date', () => {
    // 4am UTC on the 18th is still the 17th in Los Angeles, and already the 18th in Tokyo.
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-17')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-19')).toBe('ok');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-20')).toBe('CHECK_IN_DAY_MISMATCH');
  });

  it('without a time zone, takes a 补打卡 up to 7 days before the UTC date', () => {
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-16')).toBe('ok, posted 2026-10-18');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-11')).toBe('ok, posted 2026-10-18');
    expect(verdict('2026-10-18T04:00:00.000Z', '2026-10-10')).toBe('CHECK_IN_DAY_MISMATCH');
  });

  it('with a time zone, posts on the date their wall clock shows at that moment', () => {
    // 10:31 UTC on the 18th is 23:31 on the 17th in Pago Pago (UTC-11); 11:31 is 00:31 on the 18th.
    const pagoPago = verdictIn('Pacific/Pago_Pago');
    expect(pagoPago('2026-10-18T10:31:00.000Z', '2026-10-17')).toBe('ok');
    expect(pagoPago('2026-10-18T10:31:00.000Z', '2026-10-18')).toBe('CHECK_IN_DAY_MISMATCH');
    expect(pagoPago('2026-10-18T11:31:00.000Z', '2026-10-18')).toBe('ok');
    // Just after midnight, the day before is a 补打卡.
    expect(pagoPago('2026-10-18T11:31:00.000Z', '2026-10-17')).toBe('ok, posted 2026-10-18');
    // The same moment is 19:31 on the 18th in Shanghai.
    const shanghai = verdictIn('Asia/Shanghai');
    expect(shanghai('2026-10-18T11:31:00.000Z', '2026-10-18')).toBe('ok');
    expect(shanghai('2026-10-18T11:31:00.000Z', '2026-10-19')).toBe('CHECK_IN_DAY_MISMATCH');
  });

  it('with a time zone, takes a 补打卡 for one of the 7 days before, never earlier', () => {
    const shanghai = verdictIn('Asia/Shanghai');
    expect(shanghai('2026-10-18T11:31:00.000Z', '2026-10-17')).toBe('ok, posted 2026-10-18');
    expect(shanghai('2026-10-18T11:31:00.000Z', '2026-10-11')).toBe('ok, posted 2026-10-18');
    expect(shanghai('2026-10-18T11:31:00.000Z', '2026-10-10')).toBe('CHECK_IN_DAY_MISMATCH');
    const pagoPago = verdictIn('Pacific/Pago_Pago');
    expect(pagoPago('2026-10-18T10:31:00.000Z', '2026-10-10')).toBe('ok, posted 2026-10-17');
    expect(pagoPago('2026-10-18T10:31:00.000Z', '2026-10-09')).toBe('CHECK_IN_DAY_MISMATCH');
  });
});
