import type { AdminTables } from '@wildcard/admins';
import type { AiConsentTables } from '@wildcard/ai-consent';
import type { AiUsageTables } from '@wildcard/ai-usage';
import type { AppCopyTables } from '@wildcard/app-copy';
import type { NoticeTables } from '@wildcard/notices';
import type { NudgeTables } from '@wildcard/nudges';
import type { SavedPlaceTables } from '@wildcard/saved-places';
import type { WeatherTables } from '@wildcard/weather';
import type { CheckInTables, PhotoPath } from '@wildcard/check-ins';
import type { CoachTables } from '@wildcard/coach';
import type { DisclaimerDraftTables } from '@wildcard/disclaimer-drafts';
import type { FeedbackTables } from '@wildcard/feedback';
import type { MemberTables } from '@wildcard/members';
import type { MemeTables } from '@wildcard/memes';
import type { PushTables } from '@wildcard/push';
import type { SquadTables } from '@wildcard/squads';
import type { SceneTables } from '@wildcard/scenes';
import type { SportTables } from '@wildcard/sports';
import type { SwitchTables } from '@wildcard/switches';
import type { CampaignTables } from '@wildcard/campaigns';
import type { UnlockTables } from '@wildcard/unlocks';
import type { ArtTables } from '@wildcard/art';
import type { WeeklyAwardTables } from '@wildcard/weekly-awards';
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

/**
 * Whether a bearer token is the scheduler's, which alone may start jobs such as the daily push.
 * Never throws for a wrong token: it answers false.
 */
export type IsScheduler = (token: string) => Promise<boolean>;

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

/**
 * Where errors the server couldn't handle go to be grouped and seen (Sentry today), beside the
 * log. A report never names a member, a path or a body: only what failed, the request's method
 * and route, and its trace id, which finds the request's log lines (the app sees it as
 * `X-Request-Id`).
 */
export interface ErrorReports {
  /** Queues a report and returns at once; it never throws, and a report that can't go is lost. */
  readonly report: (error: unknown, context: ErrorContext) => void;
  /** Sends what is queued, waiting at most `timeoutMs`; before the process stops. */
  readonly flush: (timeoutMs: number) => Promise<void>;
}

/** Where an error happened, as far as a report may say. */
export interface ErrorContext {
  /** The log message, which says what failed (such as `request failed`). */
  readonly message: string;
  readonly method?: string | undefined;
  /** The route's pattern (`/squads/:squadId`), never the path, which holds ids and codes. */
  readonly route?: string | undefined;
  /** The request's trace id: the `requestId` on its log lines and its `X-Request-Id`. */
  readonly traceId?: string | undefined;
}

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
  AdminTables &
  AiConsentTables &
  AiUsageTables &
  NudgeTables &
  SavedPlaceTables &
  WeatherTables &
  WeeklyAwardTables &
  SportTables &
  SceneTables &
  SwitchTables &
  UnlockTables &
  CoachTables &
  NoticeTables &
  ArtTables &
  AppCopyTables &
  CampaignTables &
  FeedbackTables;

/** One file to attach to an issue, such as a screenshot. */
export interface IssueAttachment {
  /** Its name in the issue's folder, such as `screenshot-1.jpg`. */
  readonly name: string;
  readonly bytes: Uint8Array;
}

/**
 * Where members' feedback is filed for whoever fixes it: an issue tracker (a private GitHub
 * repository today). Throws `IssueTrackerUnavailableError` when it can't be reached or refuses.
 */
export interface IssueTracker {
  /**
   * Opens an issue. Each attachment is kept in `folder` first; `body` names them with
   * `{{attachment:<name>}}`, which becomes the attachment's image.
   */
  readonly open: (issue: {
    readonly title: string;
    readonly body: string;
    readonly labels: readonly string[];
    readonly folder: string;
    readonly attachments: readonly IssueAttachment[];
  }) => Promise<{ readonly number: number; readonly url: string }>;
  /**
   * The issue with `label` whose body holds `marker`, among those updated since `since`, so a
   * retry finds the one an earlier try opened before it could be remembered.
   */
  readonly find: (issue: {
    readonly label: string;
    readonly marker: string;
    readonly since: Date;
  }) => Promise<{ readonly number: number; readonly url: string } | undefined>;
}

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
   * there are. A photo that isn't in storage (never uploaded, or deleted since) has no URL in
   * the map, so one missing file never fails the rest.
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
  /** Deletes these photos; one already gone is skipped. Safe to repeat. */
  readonly delete: (paths: readonly PhotoPath[]) => Promise<void>;
}

/**
 * Counts one more request from `key` (such as a client's address) and says whether it is within
 * the limit, or how many seconds until it is. For routes anyone can call without signing in.
 */
export type RateLimit = (
  key: string,
) => { readonly allowed: true } | { readonly allowed: false; readonly retryAfterSeconds: number };

/** Something that just happened for one member, as soon as it is committed. */
export type LiveEvent =
  /** A notice was told to the member (通知): its id in the notices. */
  | { readonly kind: 'notice'; readonly id: number }
  /** What the member's 商店街 shows may have changed: read `GET /me/unlocks` again. */
  | { readonly kind: 'shelf' };

/** What hears a member's live events: each one, then the end of the feed. */
export interface LiveListener {
  readonly event: (event: LiveEvent) => void;
  /**
   * The feed ended without being stopped (the server is shutting down, or lost its connection to
   * where events come from), so events after it are missed: the client reconnects and reads again.
   */
  readonly end: () => void;
}

/**
 * Members' live events, across every instance of the server, for `GET /me/events`. Delivery is at
 * most once and only while subscribed: a client that reconnects reads what it missed from the
 * routes that keep it (such as `GET /me/notices`).
 */
export interface LiveEvents {
  /**
   * Starts hearing `member`'s events; resolves once every event committed from then on will
   * reach `listener`, and gives the function that stops it.
   *
   * @throws {LiveEventsUnavailableError} When events can't be heard right now.
   */
  readonly subscribe: (member: UserId, listener: LiveListener) => Promise<() => void>;
  /** Ends every subscription (each listener's `end`) and stops hearing events, on shutdown. */
  readonly close: () => Promise<void>;
}
