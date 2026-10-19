import { containsLink, typedText } from '@wildcard/typed-text';
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

/** The most characters a catchphrase may have, as people count them (an emoji is one). */
export const CATCHPHRASE_MAX_CHARACTERS = 10;

/**
 * What the member's character shouts when the squad cheers a teammate's 练了 (口头禅): trimmed, 1
 * to 10 characters on one line, emoji welcome, no links. Only the squad sees it, so no other check.
 */
export const Catchphrase = typedText({
  max: CATCHPHRASE_MAX_CHARACTERS,
  oneLine: true,
  description:
    'What the member’s character shouts when the squad cheers a teammate’s 练了 (口头禅): 1 to ' +
    `${String(CATCHPHRASE_MAX_CHARACTERS)} characters on one line, emoji welcome, no links.`,
}).refine((text) => !containsLink(text), { message: 'Must not hold a link' });
export type Catchphrase = z.infer<typeof Catchphrase>;

/** A member's own settings. Name and the rest of the character join it with the sign-up flow. */
export const Profile = z.strictObject({
  timeZone: TimeZone,
  /** Null until the member picks one; the app then uses their persona's own line. */
  catchphrase: Catchphrase.nullable(),
});
export type Profile = z.infer<typeof Profile>;
