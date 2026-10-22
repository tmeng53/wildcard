import { containsLink, nameText, typedText } from '@wildcard/typed-text';
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

/** The most characters a nickname may have, as people count them. */
export const NICKNAME_MAX_CHARACTERS = 12;

/** What squadmates call the member, under their character: a short name on one line, no links. */
export const Nickname = nameText({
  max: NICKNAME_MAX_CHARACTERS,
  description:
    `What squadmates call the member: 1 to ${String(NICKNAME_MAX_CHARACTERS)} characters on one ` +
    'line, emoji welcome, no links.',
}).refine((text) => !containsLink(text), { message: 'Must not hold a link' });
export type Nickname = z.infer<typeof Nickname>;

/**
 * An id from the character art (`ios/Packages/Avatar/Sources/AvatarArt`): a slot (`hair`), a
 * variant (`ponytail`) or a persona (`deadpan`). The API keeps no list of them, so new art is a
 * data-only change in the app; an app that doesn't know an id draws the slot's default.
 */
export const ArtId = z
  .string()
  .regex(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/, 'Must be lowercase letters and digits, joined by dashes')
  .max(32);

/** A preset swatch, as `#RRGGBB` in capitals. */
export const Swatch = z.string().regex(/^#[0-9A-F]{6}$/, 'Must be #RRGGBB in capitals');

/** The most slots a look may fill: room for every slot the art has today and a few more. */
export const LOOK_MAX_SLOTS = 24;

/** A look's fields: what the app sends and, beside a version, what the store keeps. */
export const lookFields = {
  persona: ArtId.meta({ description: 'How the character moves (人设), such as `deadpan`.' }),
  variants: z.record(ArtId, ArtId).meta({
    description:
      'The variant each slot wears, such as `{"body": "peach", "hair": "ponytail"}`. `body` ' +
      'is always there; a slot left out wears the art’s default, or nothing.',
  }),
  colors: z.record(ArtId, Swatch).meta({
    description:
      'The swatch a slot is recolored to, for slots in `variants` only. A slot left out keeps ' +
      'its art’s own colors.',
  }),
};

/** How a member's character looks and moves, as the character editor made it. */
export const Look = z
  .strictObject(lookFields)
  .refine(({ variants }) => Object.hasOwn(variants, 'body'), {
    message: 'Must pick a body',
    path: ['variants'],
  })
  .refine(({ variants }) => Object.keys(variants).length <= LOOK_MAX_SLOTS, {
    message: `Must fill at most ${String(LOOK_MAX_SLOTS)} slots`,
    path: ['variants'],
  })
  .refine(
    ({ variants, colors }) => Object.keys(colors).every((slot) => Object.hasOwn(variants, slot)),
    {
      message: 'Must color only slots it wears',
      path: ['colors'],
    },
  );
export type Look = z.infer<typeof Look>;

/** The member's character: its name and its look, made together in the character editor. */
export const Character = z.strictObject({ nickname: Nickname, look: Look });
export type Character = z.infer<typeof Character>;

/** A member's own settings. */
export const Profile = z.strictObject({
  timeZone: TimeZone,
  /** Null until the member picks one; the app then uses their persona's own line. */
  catchphrase: Catchphrase.nullable(),
  /** Null until the member makes their character, right after signing in. */
  character: Character.nullable(),
});
export type Profile = z.infer<typeof Profile>;

/** What squadmates see of a member besides their check-ins. */
export interface Squadmate {
  readonly catchphrase: Catchphrase | null;
  readonly character: Character | null;
}
