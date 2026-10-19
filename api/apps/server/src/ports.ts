import type { AdminTables } from '@wildcard/admins';
import type { CheckInTables, PhotoPath } from '@wildcard/check-ins';
import type { DisclaimerDraftTables } from '@wildcard/disclaimer-drafts';
import type { MemberTables } from '@wildcard/members';
import type { MemeTables } from '@wildcard/memes';
import type { PushTables } from '@wildcard/push';
import type { SquadTables } from '@wildcard/squads';
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
  /**
   * The OAuth client the token was issued to, when the member signed in through another app
   * (an MCP client such as Claude) rather than ours. Undefined for our own app's sign-ins.
   */
  readonly oauthClient: string | undefined;
}

/**
 * Sign-in: checks a bearer token and says who it belongs to. Throws `AuthTokenInvalidError`
 * for a token that isn't a current sign-in, `AuthKeysUnavailableError` when it can't be checked.
 */
export type VerifyToken = (token: string) => Promise<Caller>;

/** The sign-in provider's own records of its users, for what a token alone can't settle. */
export interface Accounts {
  /**
   * Checks a bearer token with the provider itself, so a session that has signed out is refused
   * even before its token expires. Slower than `VerifyToken`; for routes that can't be undone.
   * Throws `AuthTokenInvalidError` for a token that isn't a current sign-in,
   * `AuthUnavailableError` when the provider can't be reached. It can't tell which client a
   * token was issued to, so routes check the token with `VerifyToken` first.
   */
  readonly verifySession: (token: string) => Promise<{ readonly userId: UserId }>;
  /**
   * Deletes the user at the provider. The database deletes what references them with it (each
   * table's `on delete` in supabase/migrations). Deleting a user who is already gone does
   * nothing. Throws `AuthUnavailableError` when the provider can't be reached.
   */
  readonly deleteUser: (userId: UserId) => Promise<void>;
  /**
   * Whether the user signs in with Apple, so deleting them must revoke Apple's grant. False
   * for a user who is gone. Throws `AuthUnavailableError` when the provider can't be reached.
   */
  readonly signsInWithApple: (userId: UserId) => Promise<boolean>;
}

/**
 * Revokes the tokens Sign in with Apple issued for this app, so the member's Apple ID no longer
 * lists it (required when an account is deleted, Apple TN3194). Takes a fresh authorization
 * code from the app. Throws `AppleAuthorizationCodeInvalidError` for a code Apple refuses,
 * `AppleSignInUnavailableError` when Apple can't be reached.
 */
export type RevokeAppleSignIn = (authorizationCode: string) => Promise<void>;

/** A member signed in on the consent page: their access token, used once and then signed out. */
export interface ConsentSession {
  readonly accessToken: string;
}

/** What an OAuth client asks a member to approve on the consent page. */
export type ConsentRequest =
  | {
      readonly kind: 'ask';
      readonly clientName: string;
      /** Where the client gets its answer back. */
      readonly redirectUri: string;
      readonly scope: string;
    }
  /** The member approved this client before, so the provider answered already. */
  | { readonly kind: 'answered'; readonly redirectUrl: URL };

/**
 * The authorization server's side of the admin MCP sign-in (an OAuth 2.1 server): signs an
 * admin in on the consent page, reads what the client asks and records the admin's answer.
 * Throws `AuthUnavailableError` when the provider can't be reached.
 */
export interface OAuthConsent {
  /** Undefined for a wrong email or password. For local and test stacks only. */
  readonly signInWithPassword: (credentials: {
    readonly email: string;
    readonly password: string;
  }) => Promise<ConsentSession | undefined>;
  /** Where to send the browser to sign in with Apple; it comes back to `redirectTo` with a code. */
  readonly appleSignInUrl: (options: {
    readonly redirectTo: URL;
    readonly codeChallenge: string;
  }) => URL;
  /** The session for the code Apple's sign-in came back with; undefined when it is refused. */
  readonly exchangeCode: (options: {
    readonly code: string;
    readonly codeVerifier: string;
  }) => Promise<ConsentSession | undefined>;
  /** Throws `ConsentRequestNotFoundError` for a request that is unknown or expired. */
  readonly request: (authorizationId: string, session: ConsentSession) => Promise<ConsentRequest>;
  /** Records the answer; resolves to where the browser goes next, back to the client. */
  readonly answer: (
    authorizationId: string,
    options: { readonly session: ConsentSession; readonly approve: boolean },
  ) => Promise<URL>;
  /** Ends the session, so the sign-in made for one answer can't be used again. */
  readonly signOut: (session: ConsentSession) => Promise<void>;
}

/**
 * The tables the API reads and writes, each module's generated from the migrations
 * (`pnpm db-types`), never written by hand.
 */
export type Tables = CheckInTables &
  DisclaimerDraftTables &
  MemberTables &
  MemeTables &
  PushTables &
  SquadTables &
  AdminTables;

/** The database: any Postgres, through Kysely. */
export type Database = Kysely<Tables>;

// A photo's path and who owns it are check-in rules, so the check-ins module defines them.
export { PhotoPath, isOwnPhoto } from '@wildcard/check-ins';

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
  /**
   * A URL the app can `GET` each photo from for `expiresInSeconds`, in one call however many
   * there are. Throws `PhotoNotFoundError` when one of them isn't uploaded.
   */
  readonly createViewUrls: (
    paths: readonly PhotoPath[],
    expiresInSeconds: number,
  ) => Promise<ReadonlyMap<PhotoPath, URL>>;
  /**
   * Deletes every photo in a member's folder, saved on a check-in or only uploaded. Safe to
   * repeat.
   */
  readonly deleteAllOf: (member: UserId) => Promise<void>;
}

/**
 * Counts one more request from `key` (such as a client's address) and says whether it is within
 * the limit, or how many seconds until it is. For routes anyone can call without signing in.
 */
export type RateLimit = (
  key: string,
) => { readonly allowed: true } | { readonly allowed: false; readonly retryAfterSeconds: number };
