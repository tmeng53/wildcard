import type { CheckInTables } from '@wildcard/check-ins';
import type { Kysely } from 'kysely';
import { z } from 'zod';

// What the server needs from the outside world, written without naming a provider. Each port
// has one adapter in src/adapters/ today (Supabase Auth, Postgres, Supabase Storage); main.ts
// picks them, so
// changing provider means a new adapter, not a change to the routes.

export const UserId = z.uuid().brand<'UserId'>();
export type UserId = z.infer<typeof UserId>;

/** Who is calling: the signed-in member a bearer token was issued to. */
export interface Caller {
  readonly userId: UserId;
}

/**
 * Sign-in: checks a bearer token and says who it belongs to. Throws `AuthTokenInvalidError`
 * for a token that isn't a current sign-in, `AuthKeysUnavailableError` when it can't be checked.
 */
export type VerifyToken = (token: string) => Promise<Caller>;

/**
 * The tables the API reads and writes, each module's generated from the migrations
 * (`pnpm db-types`), never written by hand.
 */
export type Tables = CheckInTables;

/** The database: any Postgres, through Kysely. */
export type Database = Kysely<Tables>;

/**
 * A check-in photo's name in storage: `<member id>/<photo id>`, both UUIDs. The first part is
 * the folder of the member who uploaded it; the server picks both parts, never the app.
 */
export const PhotoPath = z
  .string()
  .regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  )
  .brand<'PhotoPath'>();
export type PhotoPath = z.infer<typeof PhotoPath>;

/** Whether a photo is in this member's own folder: the only photos they may use or delete. */
export function isOwnPhoto(path: PhotoPath, member: UserId): boolean {
  return path.startsWith(`${member}/`);
}

/**
 * Where check-in photos are kept. Files are private: the app reaches them only through the
 * short-lived URLs these return. Each method throws `PhotoStorageUnavailableError` when the
 * store can't be reached.
 */
export interface PhotoStorage {
  /**
   * A URL the app uploads one new photo to, with `PUT`, the file as the body and its
   * `Content-Type`. It works for a limited time and never overwrites a photo already there.
   */
  readonly createUploadUrl: (path: PhotoPath) => Promise<URL>;
  /** Whether a photo has been uploaded to this path. */
  readonly exists: (path: PhotoPath) => Promise<boolean>;
  /** A URL the app can `GET` the photo from for `expiresInSeconds`. Throws `PhotoNotFoundError`. */
  readonly createViewUrl: (path: PhotoPath, expiresInSeconds: number) => Promise<URL>;
}
