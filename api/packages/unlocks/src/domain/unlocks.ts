import { SportId } from '@wildcard/sport-ids';
import { z } from 'zod';

// What members unlock by training: the character editor's stores (商店街) and props. The app
// knows each by its id in the art; the rules and who earned what live in the database.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const UNLOCK_KINDS = ['store', 'prop'] as const;
export const UnlockKind = z.enum(UNLOCK_KINDS);
export type UnlockKind = z.infer<typeof UnlockKind>;

/** A store's or prop's id in the app's art, such as `deuce` or `racket`. */
export const ItemId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type ItemId = z.infer<typeof ItemId>;

/** The most check-ins a rule may ask for. */
export const AFTER_MAX = 100;

/** How a store or prop opens: `after` 练了 check-ins in one of `sports` (any when empty). */
export interface UnlockRule {
  readonly kind: UnlockKind;
  readonly id: ItemId;
  readonly sports: readonly SportId[];
  readonly after: number;
  /** Only check-ins made from then on count: when the rule was added. */
  readonly countsFrom: Date;
}

/** A store or prop a member unlocked, with the rule as it was then. Never taken back. */
export interface Unlock {
  readonly kind: UnlockKind;
  readonly id: ItemId;
  readonly sports: readonly SportId[];
  readonly after: number;
  /** The check-in that reached `after`. */
  readonly checkIn: string;
  /** When that check-in was made. */
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
    const counted = trained.filter(
      ({ sport, madeAt }) =>
        madeAt >= rule.countsFrom && (rule.sports.length === 0 || rule.sports.includes(sport)),
    );
    const reached = counted[rule.after - 1];
    if (reached === undefined) return [];
    return [
      {
        kind: rule.kind,
        id: rule.id,
        sports: rule.sports,
        after: rule.after,
        checkIn: reached.id,
        unlockedAt: reached.madeAt,
      },
    ];
  });
}

/** A rule as an admin adds or changes it. Its start is kept from when it was added. */
export const UnlockRuleEdit = z.strictObject({
  kind: UnlockKind.describe('`store` for a 商店街 store, `prop` for a prop.'),
  id: ItemId.describe('The store’s or prop’s id in the app’s art, such as `deuce` or `racket`.'),
  sports: z
    .array(SportId)
    .max(20)
    .refine((ids) => new Set(ids).size === ids.length, { message: 'a sport is listed twice' })
    .describe('Sport ids from the sports list whose 练了 count; empty for any sport.'),
  after: z.int().min(1).max(AFTER_MAX).describe('How many 练了 check-ins in those sports open it.'),
});
export type UnlockRuleEdit = z.infer<typeof UnlockRuleEdit>;
