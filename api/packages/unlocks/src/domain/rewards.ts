import type { SportId } from '@wildcard/sport-ids';
import { z } from 'zod';

import { ItemId, PieceId, type MemberId } from './unlocks.js';

// Everything a member can get is a reward, and each reward says how it is got through its
// triggers, one per way (Tracy, 2026-11-08: "每一个礼品和徽章这些都是有 trigger condition 的"), so
// whether a piece comes from a store, a coach, an event or the team is a row, never a table of
// its own.

/** What a member can get: a store, prop or piece for the wardrobe, a badge or a 高级券. */
export const REWARD_KINDS = ['store', 'prop', 'piece', 'badge', 'voucher'] as const;
export const RewardKind = z.enum(REWARD_KINDS);
export type RewardKind = z.infer<typeof RewardKind>;

/** A badge's or voucher's id, such as `bug-hunter` or `premium-week`. */
export const CatalogRewardId = z
  .string()
  .regex(/^[a-z][a-z0-9]*(-[a-z0-9]+){0,3}$/)
  .max(48);
export type CatalogRewardId = z.infer<typeof CatalogRewardId>;

/** Whether `id` has the shape of `kind`'s ids. */
export function rewardIdFits(kind: RewardKind, id: string): boolean {
  if (kind === 'piece') return PieceId.safeParse(id).success;
  if (kind === 'badge' || kind === 'voucher') return CatalogRewardId.safeParse(id).success;
  return ItemId.safeParse(id).success;
}

/**
 * Something that happened which gives rewards, by name: today `bug-adopted` and `idea-adopted`,
 * a piece of feedback we used. Which rewards each gives is data (the `event` triggers).
 */
export const EventName = z
  .string()
  .regex(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/)
  .max(40);
export type EventName = z.infer<typeof EventName>;

/** The ways a reward is got. */
export const TRIGGER_KINDS = [
  /** The days the member has 练了 in its sports (many on one day count once). */
  'training',
  /** A squad's AI coach may give it (a piece, at most one a member a week). */
  'coach',
  /** Only the Wildcard team gives it, through admin tools; no coach or rule ever does. */
  'team',
  /** Something that happened gives it, once each time it happens (feedback we used). */
  'event',
] as const;
export type TriggerKind = (typeof TRIGGER_KINDS)[number];

/** One way a reward is got, with what that way needs. */
export type Trigger =
  | {
      readonly kind: 'training';
      /** False retires the rule: it opens nothing more, and who it opened for keeps it. */
      readonly offered: boolean;
      readonly sports: readonly SportId[];
      readonly after: number;
      readonly countsFrom: Date;
    }
  | { readonly kind: 'coach'; readonly offered: boolean; readonly description?: string }
  | { readonly kind: 'team'; readonly offered: boolean }
  | { readonly kind: 'event'; readonly offered: boolean; readonly events: readonly EventName[] };

/** Anything a member can get, and every way they get it. */
export interface Reward {
  readonly kind: RewardKind;
  readonly id: string;
  readonly triggers: readonly Trigger[];
}

/**
 * What the team or an event gives: a piece no store sells, a badge or a voucher. Stores and props
 * open by training (props for the wardrobe that the team gives are pieces in the prop slot).
 */
export const GivenKind = RewardKind.extract(['piece', 'badge', 'voucher']);
export type GivenKind = z.infer<typeof GivenKind>;

/**
 * An `event` or `team` trigger as an admin puts it: the reward, the way, the events (for `event`
 * only) and whether it is given.
 */
export const RewardTriggerEdit = z
  .strictObject({
    kind: GivenKind,
    id: CatalogRewardId,
    way: z.enum(['event', 'team']),
    events: z
      .array(EventName)
      .min(1)
      .max(10)
      .optional()
      .meta({ description: 'The events that give it: needed for way event, not for team.' }),
    offered: z.boolean(),
  })
  .refine(({ way, events }) => (way === 'event') === (events !== undefined), {
    message: 'Name the events for way event, and none for way team.',
    path: ['events'],
  });
export type RewardTriggerEdit = z.infer<typeof RewardTriggerEdit>;

/** A badge's words, in each language the app speaks. */
export const BadgeNames = z.strictObject({
  'zh-Hans': z.string().trim().min(1).max(12),
  'zh-Hant': z.string().trim().min(1).max(12),
  en: z.string().trim().min(1).max(24),
});
export type BadgeNames = z.infer<typeof BadgeNames>;

/**
 * A dedicated badge (捉虫队, 点子王): the team's own, drawn as a ticket, never one the weekly awards'
 * model picks. `offered = false` stops new grants; who has it keeps it.
 */
export const BadgeEdit = z.strictObject({
  id: CatalogRewardId,
  names: BadgeNames,
  glyph: z
    .string()
    .regex(/^[a-z0-9]+(\.[a-z0-9]+)*$/)
    .max(60)
    .meta({ description: 'Its SF Symbol, by name.' }),
  tone: z
    .string()
    .regex(/^#[0-9A-F]{6}$/)
    .meta({ description: 'Its colour, #RRGGBB in capitals.' }),
  offered: z.boolean(),
});
export type Badge = z.infer<typeof BadgeEdit>;

/** The most days of squad premium a voucher is worth. */
export const VOUCHER_DAYS_MAX = 366;

/** A 高级券: how many days of squad premium it adds once redeemed. */
export const VoucherEdit = z.strictObject({
  id: CatalogRewardId,
  premiumDays: z.int().min(1).max(VOUCHER_DAYS_MAX),
  offered: z.boolean(),
});
export type Voucher = z.infer<typeof VoucherEdit>;

/** One time something happened that gives rewards: the event and which time (feedback's id). */
export interface Occurrence {
  readonly member: MemberId;
  readonly event: EventName;
  readonly id: string;
  readonly at: Date;
}

/** A reward as given to a member, by kind and id. */
export interface Given {
  readonly kind: GivenKind;
  readonly id: string;
}

/** A dedicated badge a member holds, and how many times (×N). */
export interface HeldBadge {
  readonly badge: Badge;
  readonly times: number;
  /** When they got it the last time. */
  readonly latestAt: Date;
}

/** A piece the team gave a member (for feedback we used, or by hand): no store sells it. */
export interface TeamPiece {
  readonly piece: PieceId;
  readonly givenAt: Date;
  /** The event that gave it; left out for one an admin gave by hand. */
  readonly event?: EventName;
}
