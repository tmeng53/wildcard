import { z } from 'zod';

// Broadcasts: notices admins write once for every member, each told on their first open of the
// app while it runs (Tracy, 2026-11-04). Nothing here knows what a holiday is: a holiday is one
// of these, with a button to the 商店街 and maybe gifts unlocked there.

/** A broadcast's id, chosen by the admin who writes it, such as `thanksgiving-soon`. */
export const BroadcastId = z
  .string()
  .regex(/^[a-z0-9][a-z0-9-]{0,63}$/)
  .brand<'BroadcastId'>();
export type BroadcastId = z.infer<typeof BroadcastId>;

/** Words in each language the app speaks: it shows the one picked in the app. */
const words = (max: number) =>
  z.strictObject({
    zhHans: z.string().trim().min(1).max(max),
    en: z.string().trim().min(1).max(max),
    zhHant: z.string().trim().min(1).max(max),
  });

/**
 * Where a button goes in the app: `stores` (商店街), `store/<storeId>`, `schedule` (出赛表),
 * `squad` (小队), `coaches` (教练招聘会), `feed` (动态), `post/<checkInId>`, `today`, `me`,
 * `wardrobe` (衣橱), `wardrobe/<pieceId>` (衣橱, trying that piece on) or `badges` (the badge
 * board). The app shows no button for one it doesn't know, so a place added later is safe to
 * send to older builds.
 */
export const Destination = z
  .string()
  .regex(
    /^(stores|notices|store\/[a-z][A-Za-z0-9]{0,39}|schedule|squad|coaches|feed|post\/[0-9a-f-]{36}|today|me|wardrobe|wardrobe\/[a-z][a-z0-9-]{0,47}|badges)$/,
  );
export type Destination = z.infer<typeof Destination>;

/** How the app first shows it: the home's notice banner, or the full-screen celebration. */
export const BroadcastStyle = z.enum(['banner', 'celebration']);
export type BroadcastStyle = z.infer<typeof BroadcastStyle>;

/** A store, prop or piece the app draws, by kind and id as the unlocks module names them. */
const ArtItem = z.strictObject({
  kind: z.enum(['store', 'prop', 'piece']),
  id: z.string().min(1).max(48),
});

/** A store or piece given with it. Props need no gift: every member holds every one. */
export const BroadcastGift = ArtItem.extend({ kind: z.enum(['store', 'piece']) });
export type BroadcastGift = z.infer<typeof BroadcastGift>;

/** What a broadcast says and when it runs, as an admin writes it and it is stored. */
export const BroadcastValue = z
  .strictObject({
    version: z.literal(1),
    title: words(30).describe('The one line every notice has, in each language.'),
    body: words(60).optional().describe('A muted second line, in each language; optional.'),
    action: z
      .strictObject({
        label: words(16).describe('The button’s words, a few characters, in each language.'),
        destination: Destination.describe(
          'Where it opens: `stores`, `store/<storeId>`, `notices` (通知), `schedule`, `squad`, `feed`, ' +
            '`post/<checkInId>`, `today`, `me`, `wardrobe` (衣橱), `wardrobe/<pieceId>` (衣橱, ' +
            'trying that piece on) or `badges` (the badge board).',
        ),
      })
      .optional()
      .describe('A button that opens a place in the app; optional.'),
    style: BroadcastStyle.describe(
      '`banner`: the home’s notice banner. `celebration`: the full-screen opening (a build ' +
        'without it shows the banner).',
    ),
    icon: ArtItem.optional().describe(
      'A store’s sign, a prop or a piece the app already draws, beside its words (such as ' +
        '`{ "kind": "store", "id": "powder" }`); left out, a sparkle. A build without it shows the sparkle.',
    ),
    gifts: z
      .array(BroadcastGift)
      .max(10)
      .describe(
        'Stores or pieces unlocked for each member when they are told (they show as ' +
          'NEW in the 商店街); may be empty.',
      ),
    members: z
      .array(z.uuid())
      .min(1)
      .max(50)
      .optional()
      .describe(
        'Only these members (by member id) are told it, such as admins trying it first; left ' +
          'out, every member. Widening it later tells the others too.',
      ),
    startsAt: z.iso.datetime({ offset: true }).describe('From when members are told it.'),
    endsAt: z.iso
      .datetime({ offset: true })
      .optional()
      .describe('Until when; left out, everyone who opens the app from then on is told.'),
  })
  .refine(
    ({ startsAt, endsAt }) =>
      endsAt === undefined || new Date(endsAt).getTime() > new Date(startsAt).getTime(),
    { message: 'it must end after it starts', path: ['endsAt'] },
  );
export type BroadcastValue = z.infer<typeof BroadcastValue>;

/** A broadcast as it is now, with who last saved it. */
export interface Broadcast {
  readonly id: BroadcastId;
  readonly value: BroadcastValue;
  /** The member id of the admin who last saved it; null once they deleted their account. */
  readonly by: string | null;
  readonly savedAt: Date;
}

/** Whether `broadcast` is for `member`: everyone, unless it names its members. */
export function isFor(broadcast: BroadcastValue, member: string): boolean {
  // Member ids are uuids, which an admin may paste in either case.
  const id = member.toLowerCase();
  return (
    broadcast.members === undefined || broadcast.members.some((named) => named.toLowerCase() === id)
  );
}

/** Whether `broadcast` is told to members who open the app at `now`. */
export function isRunning(broadcast: BroadcastValue, now: Date): boolean {
  const at = now.getTime();
  return (
    new Date(broadcast.startsAt).getTime() <= at &&
    (broadcast.endsAt === undefined || at < new Date(broadcast.endsAt).getTime())
  );
}
