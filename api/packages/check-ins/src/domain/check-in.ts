import { isDeepStrictEqual } from 'node:util';

import { z } from 'zod';

import { SportKey } from './sports.js';
import { Caption, CustomSportName, DisclaimerText } from './text.js';

// A check-in as the app's contract has it (`CheckIn` in ios/Packages/Contracts): 练了, 健康餐,
// 坦白放纵餐 or 今日免责声明, with the kind's own fields under one key named for the kind.
// Photos come with the Storage port, in a later change; until then a `photos` key is refused.

export const CheckInId = z.uuid().brand<'CheckInId'>();
export type CheckInId = z.infer<typeof CheckInId>;

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/** A calendar day in the member's own time zone, `YYYY-MM-DD`. */
export const LocalDay = z.iso.date();
export type LocalDay = z.infer<typeof LocalDay>;

/** A moment from the member's phone, ISO 8601 with any offset; kept to the millisecond. */
const Moment = z.iso
  .datetime({ offset: true })
  .transform((text) => new Date(Math.floor(Date.parse(text))));

/** The squads a check-in goes to, in the order the member picked: 1 to 3, no repeats. */
export const Audience = z
  .array(SquadId)
  .min(1)
  .max(3)
  .refine((squads) => new Set(squads).size === squads.length, {
    message: 'Must not list a squad twice',
  });

const MealSlot = z.enum(['breakfast', 'lunch', 'dinner', 'snack']);

const trainingFields = {
  sport: SportKey,
  customSport: CustomSportName.optional(),
  minutes: z.int().min(1).max(600),
  caption: Caption.optional(),
};

/** `sport: "custom"` needs `customSport`, and a listed sport never has one. */
function customSportMatches(
  training: { readonly sport: SportKey; readonly customSport?: string | undefined },
  context: z.RefinementCtx,
) {
  if (training.sport === 'custom' && training.customSport === undefined) {
    context.addIssue({ code: 'custom', path: ['customSport'], message: 'Name the custom sport' });
  }
  if (training.sport !== 'custom' && training.customSport !== undefined) {
    context.addIssue({
      code: 'custom',
      path: ['customSport'],
      message: 'Only a custom sport has a name',
    });
  }
}

const mealFields = { slot: MealSlot, caption: Caption.optional() };
const disclaimerFields = { text: DisclaimerText };

/** 练了: what was trained and for how long, with an optional line. */
export const Training = z.strictObject(trainingFields).superRefine(customSportMatches);
export type Training = z.infer<typeof Training>;

/** A 健康餐 or 坦白放纵餐: which meal, with an optional line. No calories, ever, in v1. */
export const Meal = z.strictObject(mealFields);
export type Meal = z.infer<typeof Meal>;

/** 今日免责声明: the member's excuse for resting today. Never a caption or photos. */
export const Disclaimer = z.strictObject(disclaimerFields);
export type Disclaimer = z.infer<typeof Disclaimer>;

/** What was checked in: the kind, and the kind's own fields under its key. */
export type Entry =
  | { readonly kind: 'trained'; readonly training: Training }
  | { readonly kind: 'healthyMeal'; readonly meal: Meal }
  | { readonly kind: 'cheatMeal'; readonly meal: Meal }
  | { readonly kind: 'disclaimer'; readonly disclaimer: Disclaimer };

const draftFields = {
  // `integer` in the OpenAPI document (Zod alone says `number`), so generated Swift has an Int.
  version: z.literal(1).meta({ type: 'integer', enum: [1] }),
  day: LocalDay,
  createdAt: Moment,
  audience: Audience,
};

/**
 * The body of `PUT /check-ins/{id}`: a check-in as the app makes it. The id is in the path and
 * the member is whoever is signed in, so neither is in the body.
 */
export const CheckInDraft = z.discriminatedUnion('kind', [
  z.strictObject({ ...draftFields, kind: z.literal('trained'), training: Training }),
  z.strictObject({ ...draftFields, kind: z.literal('healthyMeal'), meal: Meal }),
  z.strictObject({ ...draftFields, kind: z.literal('cheatMeal'), meal: Meal }),
  z.strictObject({ ...draftFields, kind: z.literal('disclaimer'), disclaimer: Disclaimer }),
]);
export type CheckInDraft = z.output<typeof CheckInDraft>;

/** A check-in as the module holds it, saved or about to be. */
export type CheckInRecord = Entry & {
  readonly id: CheckInId;
  readonly member: MemberId;
  readonly day: LocalDay;
  readonly createdAt: Date;
  readonly audience: readonly SquadId[];
};

/** The record a member's draft makes. */
export function recordFromDraft(
  draft: CheckInDraft,
  { id, member }: { readonly id: CheckInId; readonly member: MemberId },
): CheckInRecord {
  const base = { id, member, day: draft.day, createdAt: draft.createdAt, audience: draft.audience };
  switch (draft.kind) {
    case 'trained':
      return { ...base, kind: draft.kind, training: draft.training };
    case 'healthyMeal':
    case 'cheatMeal':
      return { ...base, kind: draft.kind, meal: draft.meal };
    case 'disclaimer':
      return { ...base, kind: draft.kind, disclaimer: draft.disclaimer };
  }
}

/**
 * Whether a retry carries the same check-in as the one saved under its id: the same member,
 * kind, day, moment (to the millisecond), fields and audience in the same order.
 */
export function isSameCheckIn(saved: CheckInRecord, retry: CheckInRecord): boolean {
  return isDeepStrictEqual(contents(saved), contents(retry));
}

function contents(record: CheckInRecord) {
  return { ...record, createdAt: record.createdAt.getTime(), audience: [...record.audience] };
}

// Stored JSON: `check_ins.payload` holds the kind's fields with their shape's version on top.
// One version so far, so each kind's union has one member.

const StoredTraining = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...trainingFields }).superRefine(customSportMatches),
]);
const StoredMeal = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...mealFields }),
]);
const StoredDisclaimer = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...disclaimerFields }),
]);

/** The `payload` column for an entry. */
export function storedPayload(entry: Entry) {
  switch (entry.kind) {
    case 'trained':
      return { version: 1, ...entry.training } as const;
    case 'healthyMeal':
    case 'cheatMeal':
      return { version: 1, ...entry.meal } as const;
    case 'disclaimer':
      return { version: 1, ...entry.disclaimer } as const;
  }
}

// Plain `z.object`, which drops `version`: each reads a payload its Stored schema checked first.
const TrainingOfStored = z.object(trainingFields).superRefine(customSportMatches);
const MealOfStored = z.object(mealFields);
const DisclaimerOfStored = z.object(disclaimerFields);

/** The entry a stored row holds. Throws if the row breaks the shape: our own data is broken. */
export function entryFromStored({
  kind,
  payload,
}: {
  readonly kind: Entry['kind'];
  readonly payload: unknown;
}): Entry {
  switch (kind) {
    case 'trained':
      StoredTraining.parse(payload);
      return { kind, training: TrainingOfStored.parse(payload) };
    case 'healthyMeal':
    case 'cheatMeal':
      StoredMeal.parse(payload);
      return { kind, meal: MealOfStored.parse(payload) };
    case 'disclaimer':
      StoredDisclaimer.parse(payload);
      return { kind, disclaimer: DisclaimerOfStored.parse(payload) };
  }
}
