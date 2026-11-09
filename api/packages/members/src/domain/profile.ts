import { containsLink, nameText, typedText } from '@wildcard/typed-text';
import { TimeZone } from '@wildcard/time-zones';
import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A member's own clock: their day, their 6pm push, their coach's morning note. */
export { TimeZone };

/** The most characters a catchphrase may have, as people count them (an emoji is one). */
export const CATCHPHRASE_MAX_CHARACTERS = 10;

/**
 * What the member's character shouts when the squad cheers a teammate's 训练 (口头禅): trimmed, 1
 * to 10 characters on one line, emoji welcome, no links. Only the squad sees it, so no other check.
 */
export const Catchphrase = typedText({
  max: CATCHPHRASE_MAX_CHARACTERS,
  oneLine: true,
  description:
    'What the member’s character shouts when the squad cheers a teammate’s 训练 (口头禅): 1 to ' +
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

/** The highest number on a player card; numbers go from 00 to this. */
export const JERSEY_NUMBER_MAX = 99;

/** The number on the member's player card in 我, shown with two digits (00 to 99). */
export const JerseyNumber = z.int().min(0).max(JERSEY_NUMBER_MAX);
export type JerseyNumber = z.infer<typeof JerseyNumber>;

/** The earliest birthday a member may give. */
export const BIRTHDAY_EARLIEST = '1900-01-01';

/**
 * The member's birthday, as a calendar date (`YYYY-MM-DD`), 1900 or later. Only the member gives
 * it, and only if they choose to; the route that takes it also refuses one after today.
 */
export const Birthday = z.iso
  .date()
  .refine((day) => day >= BIRTHDAY_EARLIEST, { message: `Must be ${BIRTHDAY_EARLIEST} or later` })
  .brand<'Birthday'>();
export type Birthday = z.infer<typeof Birthday>;

/** The latest birthday anyone can give at `now`: today where the day has begun first (UTC+14). */
export function latestBirthday(now: Date): string {
  return new Date(now.getTime() + 14 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** A member's own settings. */
export const Profile = z.strictObject({
  timeZone: TimeZone,
  /** Null until the member picks one; the app then uses their persona's own line. */
  catchphrase: Catchphrase.nullable(),
  /** Null until the member makes their character, right after signing in. */
  character: Character.nullable(),
  /** Null until the member picks one; the app then shows their place in their squad. */
  jerseyNumber: JerseyNumber.nullable(),
  /** Null unless the member chose to give it; saved apart from the rest (`saveBirthday`). */
  birthday: Birthday.nullable(),
});
export type Profile = z.infer<typeof Profile>;

/** A save of the profile. A number left out keeps the one saved, so builds that don't send one keep it. */
export type ProfileSave = Omit<Profile, 'jerseyNumber' | 'birthday'> & {
  readonly jerseyNumber?: JerseyNumber | null | undefined;
};

/** The most characters an equipped title's words may have: room past today's 6. */
export const EQUIPPED_TITLE_MAX = 40;

/** The words of a weekly title a member wears on their player card (头衔), as it was given. */
export const EquippedTitle = z.string().min(1).max(EQUIPPED_TITLE_MAX);
export type EquippedTitle = z.infer<typeof EquippedTitle>;

/** What squadmates see of a member besides their check-ins: also what their player card shows. */
export interface Squadmate {
  readonly catchphrase: Catchphrase | null;
  readonly character: Character | null;
  readonly jerseyNumber: JerseyNumber | null;
  /** When they first saved their profile, right after signing up. */
  readonly joinedAt: Date;
  /**
   * The title they chose to wear, by its words; null until they choose one. Whether they still
   * hold it is the awards' to say.
   */
  readonly equippedTitle: EquippedTitle | null;
}
