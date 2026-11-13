import { z } from 'zod';

/**
 * The kinds of push a member can turn off, each on its own switch: `dailyProgress` is the daily
 * push, at the hour its settings name (6pm to begin with), with the squad's week and what
 * teammates sent them, and also the pushes for comments, replies and @s on their posts; `coach`
 * is everything the squad's coach says to the member (its replies, its answers and its morning
 * note), sent silently but for the morning note, which rings. A new kind of push adds a topic here; every
 * switch starts on.
 */
export const PushTopic = z.enum(['dailyProgress', 'coach']);
export type PushTopic = z.infer<typeof PushTopic>;

/** Which kinds of push a member gets: every topic, on or off. */
export type PushSettings = Readonly<Record<PushTopic, boolean>>;

/** The settings of a member who never changed one: everything on. */
export const DEFAULT_PUSH_SETTINGS: PushSettings = { dailyProgress: true, coach: true };

/** Some switches, as a change names them: the rest keep what they were. */
export type PushSettingsChange = Readonly<Partial<Record<PushTopic, boolean>>>;
