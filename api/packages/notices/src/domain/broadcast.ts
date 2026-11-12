import { AppAddress } from '@wildcard/app-routes';
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

/** A badge or piece the team gave the member, drawn on its letter. */
export const LetterPresent = z.strictObject({
  kind: z.enum(['piece', 'badge']),
  id: z.string().min(1).max(48),
});
export type LetterPresent = z.infer<typeof LetterPresent>;

/**
 * A letter from the team (感谢信, Tracy 2026-11-11), opened from an envelope over 今天: its lines
 * under the member's name, signed 外卡团队, with what the team gave them drawn under it and
 * 立刻穿上. Give the presents with `give_reward` first; the letter only shows them.
 */
export const BroadcastLetter = z.strictObject({
  lines: words(300),
  presents: z
    .array(LetterPresent)
    .max(4)
    .refine(
      (presents) => new Set(presents.map((p) => `${p.kind}:${p.id}`)).size === presents.length,
      'each present once',
    ),
});
export type BroadcastLetter = z.infer<typeof BroadcastLetter>;

/** What a broadcast says and when it runs, as an admin writes it and it is stored. */
export const BroadcastValue = z
  .strictObject({
    version: z.literal(1),
    title: words(30).describe('The one line every notice has, in each language.'),
    body: words(60).optional().describe('A muted second line, in each language; optional.'),
    action: z
      .strictObject({
        label: words(16).describe('The button’s words, a few characters, in each language.'),
        destination: AppAddress.describe(
          'Where it opens: an address in the app, such as `stores`, `store/<storeId>`, `coach`, ' +
            '`post/<checkInId>` or `wardrobe/<pieceId>` (list_app_routes lists every one). A build ' +
            'that doesn’t know it shows no button.',
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
    letter: BroadcastLetter.optional().describe(
      'A letter from the team opened from an envelope over 今天, instead of the banner or ' +
        'celebration: `lines` (its words under the member’s name, a line break per line, signed ' +
        '外卡团队) and `presents` (badges or pieces the team gave them with give_reward, drawn ' +
        'under it with 立刻穿上). A build without letters shows `style`, so keep a title and button.',
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
