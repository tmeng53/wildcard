import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * An IANA time zone name such as `America/Los_Angeles`, as iOS's `TimeZone.current.identifier`
 * gives it: a name, not an offset, because offsets change with daylight saving. A few names have
 * no area (`UTC`, `GMT`). Whether the zone exists is checked when the profile is saved (Node's
 * and Postgres's time zone data can differ), so this checks only the shape.
 */
export const TimeZone = z
  .string()
  .regex(/^[A-Za-z][A-Za-z0-9_+-]*(\/[A-Za-z0-9_+-]+)*$/, 'Must be an IANA time zone name')
  .max(64);
export type TimeZone = z.infer<typeof TimeZone>;

/**
 * Whether the API's own clock can read times in `timeZone`. Postgres knows a few names Node
 * doesn't (`Factory`), and every member's day is worked out in Node.
 */
export function isReadableTimeZone(timeZone: TimeZone): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone });
    return true;
  } catch {
    return false;
  }
}

/** A member's own settings. Name and character join it with the sign-up flow. */
export const Profile = z.strictObject({ timeZone: TimeZone });
export type Profile = z.infer<typeof Profile>;
