import { isDeepStrictEqual } from 'node:util';

import { z } from 'zod';

import { Photos, type PhotoRef } from './photos.js';
import { SportKey } from './sports.js';
import { Caption, CustomSportName, DisclaimerText } from './text.js';

// A check-in as the app's contract has it (`CheckIn` in ios/Packages/Contracts): 练了, 健康餐,
// 坦白放纵餐 or 今日免责声明, with the kind's own fields under one key named for the kind.
// Any kind may have photos; they live in their own table, not in the stored payload.

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

// The fields kept in `check_ins.payload`, and with photos, the fields the app sends.
export const storedTrainingFields = {
  sport: SportKey,
  customSport: CustomSportName.optional(),
  caption: Caption.optional(),
};
const trainingFields = { ...storedTrainingFields, photos: Photos.optional() };

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

export const storedMealFields = { caption: Caption.optional() };
const mealFields = { ...storedMealFields, photos: Photos.optional() };
export const storedDisclaimerFields = { text: DisclaimerText };
const disclaimerFields = { ...storedDisclaimerFields, photos: Photos.optional() };

/** 练了: what was trained, with optional photos and a line. */
export const Training = z.strictObject(trainingFields).superRefine(customSportMatches);
export type Training = z.infer<typeof Training>;

/** A 健康餐 or 坦白放纵餐, with optional photos and a line. No meal type and no calories in v1. */
export const Meal = z.strictObject(mealFields);
export type Meal = z.infer<typeof Meal>;

/** 今日免责声明: the member's excuse for resting today, with optional photos. Never a caption. */
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

/** A check-in's photos, the cover first. */
export function photosOf(entry: Entry): readonly PhotoRef[] {
  switch (entry.kind) {
    case 'trained':
      return entry.training.photos ?? [];
    case 'healthyMeal':
    case 'cheatMeal':
      return entry.meal.photos ?? [];
    case 'disclaimer':
      return entry.disclaimer.photos ?? [];
  }
}

// Stored JSON: `check_ins.payload` holds the kind's fields, without photos, with their shape's
// version on top. One version so far, so each kind's union has one member.

const StoredTraining = z.discriminatedUnion('version', [
  z
    .strictObject({ version: z.literal(1), ...storedTrainingFields })
    .superRefine(customSportMatches),
]);
const StoredMeal = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...storedMealFields }),
]);
const StoredDisclaimer = z.discriminatedUnion('version', [
  z.strictObject({ version: z.literal(1), ...storedDisclaimerFields }),
]);

// Plain `z.object`, which drops other keys: `version` when reading a payload its Stored schema
// checked first, and `photos` when writing one.
const TrainingOfStored = z.object(storedTrainingFields).superRefine(customSportMatches);
const MealOfStored = z.object(storedMealFields);
const DisclaimerOfStored = z.object(storedDisclaimerFields);

/** The `payload` column for an entry: its fields without photos, which have their own table. */
export function storedPayload(entry: Entry) {
  switch (entry.kind) {
    case 'trained':
      return { version: 1, ...TrainingOfStored.parse(entry.training) } as const;
    case 'healthyMeal':
    case 'cheatMeal':
      return { version: 1, ...MealOfStored.parse(entry.meal) } as const;
    case 'disclaimer':
      return { version: 1, ...DisclaimerOfStored.parse(entry.disclaimer) } as const;
  }
}

/**
 * The entry a stored row and its photo rows hold. Throws if they break the shape: our own data
 * is broken.
 */
export function entryFromStored({
  kind,
  payload,
  photos,
}: {
  readonly kind: Entry['kind'];
  readonly payload: unknown;
  readonly photos: readonly PhotoRef[];
}): Entry {
  const withPhotos = photos.length === 0 ? {} : { photos: Photos.parse(photos) };
  switch (kind) {
    case 'trained':
      StoredTraining.parse(payload);
      return { kind, training: { ...TrainingOfStored.parse(payload), ...withPhotos } };
    case 'healthyMeal':
    case 'cheatMeal':
      StoredMeal.parse(payload);
      return { kind, meal: { ...MealOfStored.parse(payload), ...withPhotos } };
    case 'disclaimer':
      StoredDisclaimer.parse(payload);
      return { kind, disclaimer: { ...DisclaimerOfStored.parse(payload), ...withPhotos } };
  }
}
