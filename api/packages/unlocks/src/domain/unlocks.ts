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

/** The most check-ins a rule may ask for. */
export const AFTER_MAX = 100;

/** How a store, prop or piece opens: `after` 练了 check-ins in one of `sports` (any when empty). */
export interface UnlockRule {
  readonly kind: UnlockKind;
  /** An `ItemId` for a store or prop, a `PieceId` for a piece. */
  readonly id: string;
  readonly sports: readonly SportId[];
  readonly after: number;
  /** Only check-ins made from then on count: when the rule was added. */
  readonly countsFrom: Date;
}

/** A store, prop or piece a member unlocked, with the rule as it was then. Never taken back. */
export interface Unlock {
  readonly kind: UnlockKind;
  readonly id: string;
  readonly sports: readonly SportId[];
  readonly after: number;
  /** How it opened: the check-in that reached `after`, or an admin who gave it. */
  readonly by: { readonly checkIn: string } | { readonly admin: MemberId };
  /** When that check-in was made, or when it was given. */
  readonly unlockedAt: Date;
}

/** A 练了 check-in's sport and when it was made. */
export interface Trained {
  readonly id: string;
  /** A listed sport's id, or `custom`. */
  readonly sport: string;
  readonly madeAt: Date;
}

/**
 * What `trained` (the earliest made first) earns by `rules` beyond what `has` already holds: each
 * rule whose `after`-th counted check-in exists, that check-in being when it opened.
 */
export function earned({
  rules,
  trained,
  has,
}: {
  readonly rules: readonly UnlockRule[];
  readonly trained: readonly Trained[];
  readonly has: readonly Unlock[];
}): Unlock[] {
  const held = new Set(has.map(({ kind, id }) => `${kind}:${id}`));
  return rules.flatMap((rule) => {
    if (held.has(`${rule.kind}:${rule.id}`)) return [];
    const reached = counting(rule, trained)[rule.after - 1];
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

/** The check-ins in `trained` that count towards `rule`, the earliest first. */
function counting(rule: UnlockRule, trained: readonly Trained[]): Trained[] {
  return trained.filter(
    ({ sport, madeAt }) =>
      madeAt >= rule.countsFrom && (rule.sports.length === 0 || rule.sports.includes(sport)),
  );
}

/** A rule a member hasn't reached yet, and how many more 练了 it takes. */
export interface Locked {
  readonly kind: UnlockKind;
  readonly id: string;
  /** 练了 check-ins still to go, 1 or more. */
  readonly toGo: number;
  /** The sports whose 练了 count; empty for any sport. */
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
}: {
  readonly rules: readonly UnlockRule[];
  readonly trained: readonly Trained[];
}): Locked[] {
  return rules.flatMap((rule) => {
    const left = rule.after - counting(rule, trained).length;
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
      .describe('Sport ids from the sports list whose 练了 count; empty for any sport.'),
    after: z
      .int()
      .min(1)
      .max(AFTER_MAX)
      .describe('How many 练了 check-ins in those sports open it.'),
  })
  .refine(({ kind, id }) => idFits(kind, id), {
    message: 'the id doesn’t fit its kind',
    path: ['id'],
  });
export type UnlockRuleEdit = z.infer<typeof UnlockRuleEdit>;
