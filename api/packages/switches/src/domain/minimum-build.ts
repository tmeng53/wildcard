import { z } from 'zod';

// The lowest build of the app that may still be used, so a broken or outdated build can be sent
// to the App Store after launch with no release (Tracy, 2026-11-09). An app older than it shows
// only 有新版本 and a button to the App Store. Kept in the database (`minimum_build`).

/** A build number as the app carries it (CFBundleVersion): `190`, `190.1` or `190.1.2`. */
export const BuildNumber = z
  .string()
  .regex(/^[0-9]{1,9}(\.[0-9]{1,9}){0,2}$/, 'A build number such as 190 or 190.1');
export type BuildNumber = z.infer<typeof BuildNumber>;

/** The lowest build that may run; `build` null lets every build run. */
export const MinimumBuild = z.strictObject({
  version: z.literal(1),
  build: BuildNumber.nullable(),
});
export type MinimumBuild = z.infer<typeof MinimumBuild>;

/** Who changes the minimum build: an admin's member id. */
export const AdminId = z.uuid();
export type AdminId = z.infer<typeof AdminId>;
