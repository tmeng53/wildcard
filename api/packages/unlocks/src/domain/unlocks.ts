import { SportId } from '@wildcard/sport-ids';
import { z } from 'zod';

// What members unlock by training: the character editor's stores (商店街), props and clothing
// pieces. The app knows each by its id in the art; the rules and who earned what live in the
// database.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const UNLOCK_KINDS = ['store', 'prop', 'piece'] as const;
export const UnlockKind = z.enum(UNLOCK_KINDS);
export type UnlockKind = z.infer<typeof UnlockKind>;

/** A store's or prop's id in the app's art, such as `deuce` or `racket`. */
export const ItemId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type ItemId = z.infer<typeof ItemId>;

/** A clothing piece's id in the app's art: its store, then the piece, such as `lap-bib`. */
export const PieceId = z
  .string()
  .regex(/^[a-z][a-z0-9]*(-[a-z0-9]+){1,3}$/)
  .max(48);
export type PieceId = z.infer<typeof PieceId>;

/** Whether `id` has the shape of `kind`'s ids. */
export function idFits(kind: UnlockKind, id: string): boolean {
  return (kind === 'piece' ? PieceId : ItemId).safeParse(id).success;
}

/** The most days of 训练 a rule may ask for. */
export const AFTER_MAX = 100;

/**
 * How a store, prop or piece opens: 训练 in one of `sports` (any when empty) on `after` different
 * days.
 */
export interface UnlockRule {
  readonly kind: UnlockKind;
  /** An `ItemId` for a store or prop, a `PieceId` for a piece. */
  readonly id: string;
  readonly sports: readonly SportId[];
  readonly after: number;
  /** Only check-ins made from then on count: when the rule was added. */
  readonly countsFrom: Date;
}

/** Whether the switch `id` was on when a check-in was made at `at`. */
export type SwitchOn = (id: string, at: Date) => boolean;

/**
 * A rule with the switches it counts under: a piece's own and its store's, a store's own. Only
 * 训练 made while all of them are on count, so progress waits for the next time they are on.
 */
export interface CountedRule extends UnlockRule {
  readonly switchIds: readonly string[];
}

/** A store on the 商店街: open while its switch is on (always, without one). */
export interface Store {
  readonly id: string;
  readonly position: number;
  readonly switchId?: string;
  readonly offered: boolean;
}

export const SLOTS = ['top', 'bottom', 'shoes', 'hat', 'acc'] as const;

/**
 * A piece of clothing in a store: out while its own switch is on (always, without one) and its
 * store is open. A starter needs no earning; any other has a rule.
 */
export interface Piece {
  readonly id: string;
  readonly storeId: string;
  readonly slot: (typeof SLOTS)[number];
  readonly starter: boolean;
  readonly switchId?: string;
  readonly offered: boolean;
}

/** A switch id, as `switches` keeps them. */
const SwitchRef = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);

/** A store as an admin adds or changes it, whole. */
export const StoreEdit = z.strictObject({
  id: ItemId.describe('The store’s id in the app’s art, such as `powder`.'),
  position: z.int().min(1).max(1000).describe('Its place on the 商店街, from 1.'),
  switchId: SwitchRef.nullable().describe(
    'The switch it is open with (get_switches), such as `winter`; null for always open.',
  ),
  offered: z.boolean().describe('False retires it: it leaves the street for good.'),
});
export type StoreEdit = z.infer<typeof StoreEdit>;

/** A piece as an admin adds or changes it, whole. */
export const PieceEdit = z.strictObject({
  id: PieceId.describe('The piece’s id in the app’s art, such as `powder-tuna`.'),
  storeId: ItemId.describe('The store it hangs in.'),
  slot: z.enum(SLOTS).describe('Where it is worn.'),
  starter: z
    .boolean()
    .describe('True for a piece everyone has while it is out; false for one earned by a rule.'),
  switchId: SwitchRef.nullable().describe(
    'Its own switch (get_switches), apart from its store’s; null for none.',
  ),
  offered: z.boolean().describe('False retires it.'),
});
export type PieceEdit = z.infer<typeof PieceEdit>;

/** Where a piece stands for a member. */
export type PieceState = 'owned' | 'available' | 'locked';

/** What the 商店街 shows a member: each store open or not, each piece out for them and how. */
export interface Shelf {
  readonly stores: readonly {
    readonly id: string;
    readonly open: boolean;
    /** For a store whose rule the member hasn't reached: 训练 still to go. */
    readonly toGo?: number;
  }[];
  readonly pieces: readonly {
    readonly id: string;
    readonly storeId: string;
    readonly state: PieceState;
    /** For a locked piece. */
    readonly toGo?: number;
    /** What counts towards it: its rule's, else its store's (empty for any sport). */
    readonly sports: readonly SportId[];
    /** 训练 it takes; 0 for a starter. */
    readonly after: number;
  }[];
}

/**
 * The 商店街 for a member who holds `has` and claimed `claimed`, with `locked` still to go, while
 * `on` says which switches are on now. A piece is owned once unlocked or claimed, whatever the
 * switches and even once it or its store is retired, so what a member holds is worn all year. A
 * starter that is offered, out (its switch on, its store open) and in an earned store is available
 * to everyone, except a limited one (its store or itself follows a switch), which is owned while it
 * is out so it waits in its store to be claimed (领取), and is kept only if it was. A piece that is
 * all that with a rule still to reach is locked. Anything else is not shown. A retired store is
 * listed, closed, only while the member owns something in it.
 */
export function shelf({
  stores,
  pieces,
  rules,
  has,
  claimed = [],
  locked,
  on,
}: {
  readonly stores: readonly Store[];
  readonly pieces: readonly Piece[];
  readonly rules: readonly UnlockRule[];
  readonly has: readonly Unlock[];
  readonly claimed?: readonly PieceId[];
  readonly locked: readonly Locked[];
  readonly on: (id: string) => boolean;
}): Shelf {
  const key = (kind: UnlockKind, id: string) => `${kind}:${id}`;
  const held = new Set(has.map(({ kind, id }) => key(kind, id)));
  const ruleOf = new Map(rules.map((rule) => [key(rule.kind, rule.id), rule]));
  const toGoOf = new Map(locked.map(({ kind, id, toGo: left }) => [key(kind, id), left]));
  const switchOn = (id: string | undefined) => id === undefined || on(id);
  const offered = stores.filter((store) => store.offered);
  const open = new Map(offered.map((store) => [store.id, switchOn(store.switchId)]));
  const earnedStore = (id: string) => !ruleOf.has(key('store', id)) || held.has(key('store', id));
  const kept = new Set<string>(claimed);
  const limited = (piece: Piece) =>
    piece.switchId !== undefined ||
    offered.find(({ id }) => id === piece.storeId)?.switchId !== undefined;
  const listed = pieces.flatMap((piece): Shelf['pieces'][number][] => {
    const rule = ruleOf.get(key('piece', piece.id));
    const fromStore = ruleOf.get(key('store', piece.storeId));
    const counted = { sports: rule?.sports ?? fromStore?.sports ?? [], after: rule?.after ?? 0 };
    const base = { id: piece.id, storeId: piece.storeId, ...counted };
    // Owned stays on the member's rack, even once retired, switched off or in a retired store.
    if (held.has(key('piece', piece.id)) || kept.has(piece.id))
      return [{ ...base, state: 'owned' }];
    if (!open.has(piece.storeId) || !piece.offered) return [];
    const out = (open.get(piece.storeId) ?? false) && switchOn(piece.switchId);
    if (!out || !earnedStore(piece.storeId)) return [];
    if (piece.starter) return [{ ...base, state: limited(piece) ? 'owned' : 'available' }];
    const left = toGoOf.get(key('piece', piece.id));
    return left === undefined ? [] : [{ ...base, state: 'locked', toGo: left }];
  });
  const holding = new Set(
    listed.filter(({ state }) => state === 'owned').map(({ storeId }) => storeId),
  );
  const retiredHeld = stores.filter((store) => !store.offered && holding.has(store.id));
  return {
    stores: [
      ...offered.map(({ id }) => {
        const left = earnedStore(id) ? undefined : toGoOf.get(key('store', id));
        return { id, open: open.get(id) ?? false, ...(left === undefined ? {} : { toGo: left }) };
      }),
      ...retiredHeld.map(({ id }) => ({ id, open: false })),
    ],
    pieces: listed,
  };
}

/** A store, prop or piece a member unlocked, with the rule as it was then. Never taken back. */
export interface Unlock {
  readonly kind: UnlockKind;
  readonly id: string;
  readonly sports: readonly SportId[];
  readonly after: number;
  /**
   * How it opened: the check-in that reached `after` (its `training` trigger), or the Wildcard
   * team's admin who gave it (`team`).
   */
  readonly by: { readonly checkIn: string } | { readonly admin: MemberId };
  /** When that check-in was made, or when it was given. */
  readonly unlockedAt: Date;
}

/** A 训练 check-in's sport, the day it counts for and when it was made. */
export interface Trained {
  readonly id: string;
  /** A listed sport's id, or `custom`. */
  readonly sport: string;
  /** The member's own day it counts for, `YYYY-MM-DD`. */
  readonly day: string;
  readonly madeAt: Date;
}

/**
 * What `trained` (the earliest made first) earns by `rules` beyond what `has` already holds: each
 * rule whose `after`-th counted day is reached, the check-in that reached it being when it opened.
 */
export function earned({
  rules,
  trained,
  has,
  switchOn,
}: {
  readonly rules: readonly CountedRule[];
  readonly trained: readonly Trained[];
  readonly has: readonly Unlock[];
  readonly switchOn: SwitchOn;
}): Unlock[] {
  const held = new Set(has.map(({ kind, id }) => `${kind}:${id}`));
  return rules.flatMap((rule) => {
    if (held.has(`${rule.kind}:${rule.id}`)) return [];
    const reached = counting(rule, { trained, switchOn })[rule.after - 1];
    if (reached === undefined) return [];
    return [
      {
        kind: rule.kind,
        id: rule.id,
        sports: rule.sports,
        after: rule.after,
        by: { checkIn: reached.id },
        unlockedAt: reached.madeAt,
      },
    ];
  });
}

/**
 * The first check-in in `trained` that counts towards `rule` on each day, the earliest made first.
 * A rule counts days trained, not posts, so many 训练 on one day count once.
 */
function counting(
  rule: CountedRule,
  { trained, switchOn }: { readonly trained: readonly Trained[]; readonly switchOn: SwitchOn },
): Trained[] {
  const days = new Set<string>();
  return trained.filter(({ sport, day, madeAt }) => {
    const counts =
      madeAt >= rule.countsFrom &&
      (rule.sports.length === 0 || rule.sports.includes(sport)) &&
      rule.switchIds.every((id) => switchOn(id, madeAt)) &&
      !days.has(day);
    if (counts) days.add(day);
    return counts;
  });
}

/** A rule a member hasn't reached yet, and how many more days of 训练 it takes. */
export interface Locked {
  readonly kind: UnlockKind;
  readonly id: string;
  /** Days of 训练 still to go, 1 or more. */
  readonly toGo: number;
  /** The sports whose 训练 count; empty for any sport. */
  readonly sports: readonly SportId[];
}

/** A piece the member claimed (领取) into their wardrobe. Never taken back. */
export interface Claim {
  readonly piece: PieceId;
  readonly claimedAt: Date;
}

/** How far `trained` (the earliest made first) is from each of `rules` it hasn't reached. */
export function toGo({
  rules,
  trained,
  switchOn,
}: {
  readonly rules: readonly CountedRule[];
  readonly trained: readonly Trained[];
  readonly switchOn: SwitchOn;
}): Locked[] {
  return rules.flatMap((rule) => {
    const left = rule.after - counting(rule, { trained, switchOn }).length;
    return left > 0 ? [{ kind: rule.kind, id: rule.id, toGo: left, sports: rule.sports }] : [];
  });
}

/** Stores, props and pieces an admin gives a member, whatever they trained. */
export const UnlockGift = z.strictObject({
  member: MemberId.describe('The member’s id.'),
  items: z
    .array(
      z
        .strictObject({ kind: UnlockKind, id: z.string().max(48) })
        .refine(({ kind, id }) => idFits(kind, id), { message: 'the id doesn’t fit its kind' }),
    )
    .max(100)
    .optional()
    .describe(
      'The stores, props and pieces to give, each by kind and id; leave out for every one.',
    ),
});
export type UnlockGift = z.infer<typeof UnlockGift>;

/** A rule as an admin adds or changes it. Its start is kept from when it was added. */
export const UnlockRuleEdit = z
  .strictObject({
    kind: UnlockKind.describe(
      '`store` for a 商店街 store, `prop` for a prop, `piece` for a clothing piece in a store.',
    ),
    id: z
      .string()
      .max(48)
      .describe(
        'The id in the app’s art: a store or prop such as `deuce` or `racket`, a piece such as `lap-bib`.',
      ),
    sports: z
      .array(SportId)
      .max(20)
      .refine((ids) => new Set(ids).size === ids.length, { message: 'a sport is listed twice' })
      .describe('Sport ids from the sports list whose 训练 count; empty for any sport.'),
    after: z
      .int()
      .min(1)
      .max(AFTER_MAX)
      .describe(
        'On how many different days 训练 in those sports open it; many on one day count once.',
      ),
  })
  .refine(({ kind, id }) => idFits(kind, id), {
    message: 'the id doesn’t fit its kind',
    path: ['id'],
  });
export type UnlockRuleEdit = z.infer<typeof UnlockRuleEdit>;
