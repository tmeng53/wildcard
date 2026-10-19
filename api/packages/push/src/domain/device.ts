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

/** One phone a member gets push notifications on. */
export interface Device {
  readonly token: DeviceToken;
  readonly environment: PushEnvironment;
}
