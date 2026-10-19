import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * An IANA time zone name such as `America/Los_Angeles`, as iOS's `TimeZone.current.identifier`
 * gives it: a name, not an offset, because offsets change with daylight saving. `UTC` is the one
 * name with no area. Whether the zone exists is checked when the profile is saved (Node's and
 * Postgres's time zone data can differ), so this checks only the shape.
 */
export const TimeZone = z
  .string()
  .regex(/^(UTC|[A-Za-z]+(\/[A-Za-z0-9_+-]+)+)$/, 'Must be an IANA time zone name')
  .max(64);
export type TimeZone = z.infer<typeof TimeZone>;

/** A member's own settings. Name and character join it with the sign-up flow. */
export const Profile = z.strictObject({ timeZone: TimeZone });
export type Profile = z.infer<typeof Profile>;
