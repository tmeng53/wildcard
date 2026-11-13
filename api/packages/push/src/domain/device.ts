import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * An APNs device token, as hex (iOS hands the app bytes; the app sends them hex-encoded). Apple
 * says not to rely on its length, so this checks only that it is whole bytes of hex, within
 * reason. Kept lowercase, so the same token always matches itself.
 */
export const DeviceToken = z
  .string()
  .regex(/^(?:[0-9A-Fa-f]{2}){16,100}$/, 'Must be the APNs device token, hex-encoded')
  .transform((token) => token.toLowerCase())
  .brand<'DeviceToken'>();
export type DeviceToken = z.infer<typeof DeviceToken>;

/**
 * Which APNs servers a token belongs to. A build run from Xcode gets `sandbox` tokens;
 * TestFlight and the App Store get `production` ones. A token only works on its own servers.
 */
export const PushEnvironment = z.enum(['sandbox', 'production']);
export type PushEnvironment = z.infer<typeof PushEnvironment>;

/**
 * Which pushes an install can show. A push carries a key in the app's String Catalog, and a
 * build from before a key was added has no words for it; so each phone says which generation of
 * pushes its build knows, and a push goes only to phones that know it
 * (`PushNotification.since`). 1 is every push from before generations, and what a build that
 * says nothing knows; 2 adds the teammate push; 3 the 一起练 push. A push with new words takes the next number,
 * here and in the app (`PushDevice.generation`).
 */
export const PushGeneration = z.int().min(1).max(32767).brand<'PushGeneration'>();
export type PushGeneration = z.infer<typeof PushGeneration>;

/** The pushes every build knows. */
export const FIRST_PUSH_GENERATION = PushGeneration.parse(1);

/** One phone a member gets push notifications on. */
export interface Device {
  readonly token: DeviceToken;
  readonly environment: PushEnvironment;
  readonly generation: PushGeneration;
}
