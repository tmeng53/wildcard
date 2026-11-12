import { isDeepStrictEqual } from 'node:util';

import { z } from 'zod';

import { Photos, type PhotoRef } from './photos.js';
import { SportKey } from './sports.js';
import { Caption, CustomSportName, DisclaimerText } from './text.js';
import { Workout } from './workout.js';

// A check-in: 训练, 健康餐, 坦白放纵餐 or 今日请假条, with the kind's own fields under one
// key named for the kind. These schemas are the contract: the OpenAPI document comes from them,
// and the app's Swift types are generated from that (scripts/swift-openapi.sh).
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

/**
 * The most squads one post lists. A member is in one squad at a time, but posts made before that
 * may list up to this many, and their edits and events still carry them.
 */
export const AUDIENCE_MAX = 3;

/**
 * The squads a check-in goes to, in the order the member picked: up to `AUDIENCE_MAX`, no
 * repeats. A check-in made in a squad always goes to it (an empty one from an older build is sent
 * to the member's squads, off the feed); one made before joining any goes to none.
 */
export const Audience = z
  .array(SquadId)
  .max(AUDIENCE_MAX)
  .refine((squads) => new Set(squads).size === squads.length, {
    message: 'Must not list a squad twice',
  });

/** How long a 训练 took, in whole minutes: 1 to 600. Optional; never asked for. */
export const WorkoutMinutes = z
  .int()
  .min(1)
  .max(600)
  .meta({ description: 'How long the workout took, in whole minutes.' });
export type WorkoutMinutes = z.infer<typeof WorkoutMinutes>;

/**
 * When a 训练 started, on the member's own clock on its day, as `HH:mm` (24 hours). Optional;
 * a workout from Apple Health carries its own start instead.
 */
export const StartTime = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d$/)
  .meta({ description: "When it started, on the member's clock on its day, as HH:mm." });
export type StartTime = z.infer<typeof StartTime>;

// The fields kept in `check_ins.payload`, and with photos, the fields the app sends.
export const storedTrainingFields = {
  sport: SportKey,
  customSport: CustomSportName.optional(),
  minutes: WorkoutMinutes.optional(),
  startTime: StartTime.optional(),
  caption: Caption.optional(),
};
const trainingFields = {
  ...storedTrainingFields,
  photos: Photos.optional(),
  workout: Workout.optional(),
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

export const storedMealFields = { caption: Caption.optional() };
const mealFields = { ...storedMealFields, photos: Photos.optional() };
export const storedDisclaimerFields = {
  text: DisclaimerText,
  restDay: z
    .literal(true)
    .optional()
    .meta({
      description:
        '休息: a rest the member planned, not leave (请假). Left out for leave. A rest makes its day a ' +
        'rest day in their plan, and never counts as a 请假条 in the 战报.',
    }),
};
const disclaimerFields = { ...storedDisclaimerFields, photos: Photos.optional() };

/** A workout's tiles sit among the photos or right after them. */
function tileFits(
  training: {
    readonly photos?: readonly unknown[] | undefined;
    readonly workout?:
      | { readonly tilePosition?: number | undefined; readonly chartPosition?: number | undefined }
      | undefined;
  },
  context: z.RefinementCtx,
) {
  const tiles = [training.workout?.tilePosition, training.workout?.chartPosition];
  const last = (training.photos?.length ?? 0) + tiles.filter((tile) => tile !== undefined).length;
  for (const [index, key] of (['tilePosition', 'chartPosition'] as const).entries()) {
    const position = tiles[index];
    if (position !== undefined && position > last) {
      context.addIssue({
        code: 'custom',
        path: ['workout', key],
        message: 'The tiles sit among the photos or right after them',
      });
    }
  }
}

/** 训练: what was trained, with optional minutes, photos, a line and the workout it came from. */
export const Training = z
  .strictObject(trainingFields)
  .superRefine(customSportMatches)
  .superRefine(tileFits)
  .meta({ id: 'Training' });
export type Training = z.infer<typeof Training>;

/** A 健康餐 or 坦白放纵餐, with optional photos and a line. No meal type and no calories in v1. */
export const Meal = z.strictObject(mealFields).meta({ id: 'Meal' });
export type Meal = z.infer<typeof Meal>;

/** 今日请假条: the member's excuse for resting today, with optional photos. Never a caption. */
export const Disclaimer = z.strictObject(disclaimerFields).meta({ id: 'Disclaimer' });
export type Disclaimer = z.infer<typeof Disclaimer>;

/** Whether an entry is a 请假条 taken as leave (请假), not a planned rest (休息). */
export function isLeave(entry: Entry): boolean {
  return entry.kind === 'disclaimer' && entry.disclaimer.restDay !== true;
}

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
  inFeed: z
    .boolean()
    .optional()
    .meta({
      description:
        '发布到动态: true (the default) also posts it in the squads’ 动态; false only records it, ' +
        'counted for the squads like any other but not in their 动态. Older builds leave it out ' +
        'and send an empty audience for a check-in that isn’t posted.',
    }),
};

/**
 * The body of `PUT /check-ins/{id}`: a check-in as the app makes it. The id is in the path and
 * the member is whoever is signed in, so neither is in the body.
 */
export const CheckInDraft = z.discriminatedUnion('kind', [
  z
    .strictObject({ ...draftFields, kind: z.literal('trained'), training: Training })
    .meta({ id: 'TrainedCheckInDraft' }),
  z
    .strictObject({ ...draftFields, kind: z.literal('healthyMeal'), meal: Meal })
    .meta({ id: 'HealthyMealCheckInDraft' }),
  z
    .strictObject({ ...draftFields, kind: z.literal('cheatMeal'), meal: Meal })
    .meta({ id: 'CheatMealCheckInDraft' }),
  z
    .strictObject({ ...draftFields, kind: z.literal('disclaimer'), disclaimer: Disclaimer })
    .meta({ id: 'DisclaimerCheckInDraft' }),
]);
export type CheckInDraft = z.output<typeof CheckInDraft>;

/**
 * The body of `PATCH /check-ins/{id}`: a saved check-in's own fields, all of them, as they are
 * to be. Its kind must be the one saved; the day, time and audience are never changed.
 */
export const CheckInEdit = z.discriminatedUnion('kind', [
  z
    .strictObject({ version: draftFields.version, kind: z.literal('trained'), training: Training })
    .meta({ id: 'TrainedCheckInEdit' }),
  z
    .strictObject({ version: draftFields.version, kind: z.literal('healthyMeal'), meal: Meal })
    .meta({ id: 'HealthyMealCheckInEdit' }),
  z
    .strictObject({ version: draftFields.version, kind: z.literal('cheatMeal'), meal: Meal })
    .meta({ id: 'CheatMealCheckInEdit' }),
  z
    .strictObject({
      version: draftFields.version,
      kind: z.literal('disclaimer'),
      disclaimer: Disclaimer,
    })
    .meta({ id: 'DisclaimerCheckInEdit' }),
]);
export type CheckInEdit = z.output<typeof CheckInEdit>;

/** A check-in as the module holds it, saved or about to be. */
export type CheckInRecord = Entry & {
  readonly id: CheckInId;
  readonly member: MemberId;
  /** The day it counts for: the day posted on or one of the 7 before (补打卡). */
  readonly day: LocalDay;
  /**
   * The member's own day when they posted it, which orders the squad's feed. Every saved
   * check-in has one; a draft gets it from the member's time zone when it is saved.
   */
  readonly postedDay?: LocalDay;
  readonly createdAt: Date;
  readonly audience: readonly SquadId[];
  /**
   * Whether it is a post in its squads' 动态 (发布到动态). One that isn't still counts for them,
   * but only its author sees it, reacts to it or comments on it. Never changed after posting.
   */
  readonly inFeed: boolean;
};

/** The record a member's draft makes. */
export function recordFromDraft(
  draft: CheckInDraft,
  { id, member }: { readonly id: CheckInId; readonly member: MemberId },
): CheckInRecord {
  const base = {
    id,
    member,
    day: draft.day,
    createdAt: draft.createdAt,
    audience: draft.audience,
    // An older build's empty audience in a squad meant 仅自己可见, which is now off the feed.
    inFeed: draft.inFeed ?? draft.audience.length > 0,
  };
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
 * kind, day, moment (to the millisecond), fields, audience in the same order and 发布到动态.
 */
export function isSameCheckIn(saved: CheckInRecord, retry: CheckInRecord): boolean {
  // The day posted on comes from the save, not the draft, so it isn't compared.
  return isDeepStrictEqual(
    contents({ ...saved, postedDay: undefined }),
    contents({ ...retry, postedDay: undefined }),
  );
}

function contents(record: CheckInRecord) {
  return { ...record, createdAt: record.createdAt.getTime(), audience: [...record.audience] };
}

/** A 训练's workout; other kinds have none. */
export function workoutOf(entry: Entry): Workout | undefined {
  return entry.kind === 'trained' ? entry.training.workout : undefined;
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

// Stored JSON: `check_ins.payload` holds the kind's fields, without photos or the workout (each
// in its own table), with their shape's
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
// checked first, and `photos` and `workout` when writing one.
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
  workout,
}: {
  readonly kind: Entry['kind'];
  readonly payload: unknown;
  readonly photos: readonly PhotoRef[];
  readonly workout?: Workout | undefined;
}): Entry {
  const withPhotos = photos.length === 0 ? {} : { photos: Photos.parse(photos) };
  switch (kind) {
    case 'trained':
      StoredTraining.parse(payload);
      return {
        kind,
        training: {
          ...TrainingOfStored.parse(payload),
          ...withPhotos,
          ...(workout === undefined ? {} : { workout }),
        },
      };
    case 'healthyMeal':
    case 'cheatMeal':
      StoredMeal.parse(payload);
      return { kind, meal: { ...MealOfStored.parse(payload), ...withPhotos } };
    case 'disclaimer':
      StoredDisclaimer.parse(payload);
      return { kind, disclaimer: { ...DisclaimerOfStored.parse(payload), ...withPhotos } };
  }
}
