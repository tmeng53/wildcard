import { z } from 'zod';

/**
 * The kinds of push a member can turn off, each on its own switch: `dailyProgress` is the one
 * push a day, at the hour its settings name (6pm to begin with), with the squad's week and what
 * teammates sent them. A new kind of push adds a topic here; every switch starts on.
 */
export const PushTopic = z.enum(['dailyProgress']);
export type PushTopic = z.infer<typeof PushTopic>;

/** Which kinds of push a member gets: every topic, on or off. */
export type PushSettings = Readonly<Record<PushTopic, boolean>>;

/** The settings of a member who never changed one: everything on. */
export const DEFAULT_PUSH_SETTINGS: PushSettings = { dailyProgress: true };
