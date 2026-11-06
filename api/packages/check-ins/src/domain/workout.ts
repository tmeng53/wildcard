import { z } from 'zod';

// The workout behind a 训练, imported from a provider such as Apple Health (Tracy, 2026-11-06).
// Provider-neutral: every number is optional, and the app shows only those present. Only what
// the member posted is sent: a number they struck out on the compose page, or a route or chart
// whose tile they took off, never reaches the server. Heart rate stays in this module: nothing
// that feeds an AI (the coach, the weekly awards, the drafts) reads a workout.

/** A moment from the provider, ISO 8601 with any offset; kept to the millisecond. */
const Moment = z.iso
  .datetime({ offset: true })
  .transform((text) => new Date(Math.floor(Date.parse(text))));

/** The longest workout the API keeps: a day. */
const DAY_SECONDS = 24 * 60 * 60;

const heartRate = z.int().min(20).max(250);

/** The posted numbers, as the provider gave them: never converted into other units. */
export const WorkoutSummary = z
  .strictObject({
    durationSec: z.int().min(1).max(DAY_SECONDS).optional(),
    distanceM: z.number().nonnegative().max(1_000_000).optional(),
    paceSecPerKm: z.number().positive().max(DAY_SECONDS).optional(),
    speedKmh: z.number().nonnegative().max(300).optional(),
    avgHr: heartRate.optional(),
    maxHr: heartRate.optional(),
    effort: z.number().min(1).max(10).optional(),
    laps: z.int().min(1).max(10_000).optional(),
    poolLengthM: z.number().positive().max(100).optional(),
  })
  .meta({
    id: 'WorkoutSummary',
    description:
      'The numbers the member posted, as the provider gave them. Each is left out when the ' +
      'provider had none or the member struck it out. Pace is seconds per kilometre (run, walk), ' +
      'speed km/h (bike), effort 1 to 10, laps with the pool length in metres (swim).',
  });
export type WorkoutSummary = z.infer<typeof WorkoutSummary>;

/** The chart tile's data: heart rate over the workout, or each lap's time for a swim. */
export const WorkoutSeries = z
  .strictObject({
    hr: z
      .array(
        z
          .strictObject({
            t: z
              .number()
              .nonnegative()
              .max(DAY_SECONDS)
              .meta({ description: 'Seconds from the start.' }),
            bpm: heartRate,
          })
          .meta({ id: 'HeartRatePoint' }),
      )
      .min(2)
      .max(300)
      .optional()
      .meta({
        description: 'Heart rate, earliest first, thinned on the phone to about 120 points.',
      }),
    laps: z
      .array(z.number().positive().max(DAY_SECONDS))
      .min(1)
      .max(1000)
      .optional()
      .meta({ description: 'Each lap’s time in seconds, in order.' }),
  })
  .meta({ id: 'WorkoutSeries', description: 'Sent only when the chart tile was kept.' });
export type WorkoutSeries = z.infer<typeof WorkoutSeries>;

/** A point on the route. */
export const RoutePoint = z
  .strictObject({ lat: z.number().min(-90).max(90), lon: z.number().min(-180).max(180) })
  .meta({ id: 'RoutePoint' });
export type RoutePoint = z.infer<typeof RoutePoint>;

/** The most route points a workout keeps; the phone simplifies the route first. */
export const ROUTE_POINTS_MAX = 2000;

/** The most photos and the tile together: 3 photos and the tile, which doesn't count toward them. */
const TILE_POSITION_MAX = 4;

const workoutFields = {
  provider: z
    .string()
    .regex(/^[a-z][a-z_]{1,30}$/)
    .meta({ description: 'Where it came from: `apple_health` for now.', example: 'apple_health' }),
  providerWorkoutId: z
    .string()
    .min(1)
    .max(100)
    .meta({
      description: 'The provider’s own id for it (an HKWorkout’s UUID). Posted once per member.',
    }),
  summary: WorkoutSummary,
  series: WorkoutSeries.optional(),
  route: z
    .array(RoutePoint)
    .min(2)
    .max(ROUTE_POINTS_MAX)
    .optional()
    .meta({
      description:
        'The route, start first, with 200 m cut from each end on the phone. Sent only when the ' +
        'map tile was kept.',
    }),
  tilePosition: z
    .int()
    .min(1)
    .max(TILE_POSITION_MAX)
    .optional()
    .meta({
      description:
        'Where the map or chart tile sits among the photos, 1 being the cover. Present exactly ' +
        'when a route or a series is.',
    }),
};

/** The route or the chart comes with the tile that shows it, and a tile shows one of them. */
function tileMatches(
  workout: {
    readonly startedAt: Date | string;
    readonly endedAt: Date | string;
    readonly series?: unknown;
    readonly route?: unknown;
    readonly tilePosition?: number | undefined;
  },
  context: z.RefinementCtx,
) {
  const hasTile = workout.tilePosition !== undefined;
  const hasData = workout.series !== undefined || workout.route !== undefined;
  if (hasTile !== hasData) {
    context.addIssue({
      code: 'custom',
      path: ['tilePosition'],
      message: 'A tile position goes with a route or a series, and only with one',
    });
  }
  if (new Date(workout.endedAt).getTime() < new Date(workout.startedAt).getTime()) {
    context.addIssue({
      code: 'custom',
      path: ['endedAt'],
      message: 'Must not end before it starts',
    });
  }
}

/** A workout as the app sends it with a 训练. */
export const Workout = z
  .strictObject({ ...workoutFields, startedAt: Moment, endedAt: Moment })
  .superRefine(tileMatches)
  .meta({
    id: 'Workout',
    description:
      'The workout a 训练 was posted from, with only the numbers the member kept. Left out on ' +
      'a 训练 posted by hand.',
  });
export type Workout = z.output<typeof Workout>;

/** A workout as the API sends it back. */
export const WorkoutView = z
  .strictObject({
    ...workoutFields,
    startedAt: z.iso.datetime().meta({ description: 'In UTC with milliseconds.' }),
    endedAt: z.iso.datetime().meta({ description: 'In UTC with milliseconds.' }),
  })
  .meta({ id: 'WorkoutView' });

/** The workout as the API sends it. */
export function workoutView(workout: Workout): z.infer<typeof WorkoutView> {
  return {
    ...workout,
    startedAt: workout.startedAt.toISOString(),
    endedAt: workout.endedAt.toISOString(),
  };
}

// Stored JSON: each column carries its shape's version.

const StoredSummary = z.strictObject({ version: z.literal(1), ...WorkoutSummary.shape });
const StoredSeries = z.strictObject({ version: z.literal(1), ...WorkoutSeries.shape });
const StoredRoute = z.strictObject({ version: z.literal(1), points: z.array(RoutePoint) });
// Plain `z.object`, which drops `version` once its Stored schema checked the column.
const SummaryOfStored = z.object(WorkoutSummary.shape);
const SeriesOfStored = z.object(WorkoutSeries.shape);

/** A `check_in_workouts` row's columns for a workout, without the post and member. */
export function storedWorkout(workout: Workout) {
  return {
    provider: workout.provider,
    provider_workout_id: workout.providerWorkoutId,
    started_at: workout.startedAt,
    ended_at: workout.endedAt,
    summary: JSON.stringify({ version: 1, ...workout.summary }),
    series: workout.series === undefined ? null : JSON.stringify({ version: 1, ...workout.series }),
    route:
      workout.route === undefined ? null : JSON.stringify({ version: 1, points: workout.route }),
    tile_position: workout.tilePosition ?? null,
  };
}

/** The workout a `check_in_workouts` row holds. Throws if it breaks the shape: our own data is broken. */
export function workoutFromStored(row: {
  readonly provider: string;
  readonly provider_workout_id: string;
  readonly started_at: Date;
  readonly ended_at: Date;
  readonly summary: unknown;
  readonly series: unknown;
  readonly route: unknown;
  readonly tile_position: number | null;
}): Workout {
  const summary = SummaryOfStored.parse(StoredSummary.parse(row.summary));
  const series =
    row.series === null ? undefined : SeriesOfStored.parse(StoredSeries.parse(row.series));
  const route = row.route === null ? undefined : StoredRoute.parse(row.route).points;
  // Keys are left out, never undefined, so a retry compares equal to the saved check-in.
  return {
    provider: row.provider,
    providerWorkoutId: row.provider_workout_id,
    startedAt: new Date(row.started_at),
    endedAt: new Date(row.ended_at),
    summary,
    ...(series === undefined ? {} : { series }),
    ...(route === undefined ? {} : { route }),
    ...(row.tile_position === null ? {} : { tilePosition: row.tile_position }),
  };
}
