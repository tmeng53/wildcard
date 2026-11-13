import type { DailyPushSettings } from './domain/daily-push-settings.js';
import type { DailyCandidate, DuePush, LocalDay } from './domain/daily.js';
import type { Device, DeviceToken, MemberId } from './domain/device.js';
import type { PushNotification } from './domain/notification.js';
import type { TeammatePushSettings } from './domain/teammate-push-settings.js';
import type { PushSettings, PushTopic } from './domain/topic.js';

/** Where members' push devices are kept. */
export interface DeviceStore {
  /** Saves the device as the member's, moving it from whoever had it before. */
  register(member: MemberId, device: Device): Promise<void>;
  /** Forgets the device if it is the member's; does nothing otherwise. */
  unregister(member: MemberId, token: DeviceToken): Promise<void>;
  /** Every device of these members. */
  devicesOf(members: readonly MemberId[]): Promise<Device[]>;
  /** Forgets devices that can no longer be reached, whoever they belong to. */
  remove(tokens: readonly DeviceToken[]): Promise<void>;
}

/**
 * What sending to one device did: `sent`, `gone` when the token no longer reaches an install
 * (the app was deleted, or the token was never valid), `off` when sending isn't set up.
 */
export type SendOutcome = 'sent' | 'gone' | 'off';

/** Sends push notifications. Throws when the push service refuses or can't be reached. */
export interface PushSender {
  send(device: Device, notification: PushNotification): Promise<SendOutcome>;
}

/** Where members' push switches are kept: only the ones they changed, so the rest stay on. */
export interface SettingsStore {
  /** The switches the member changed. */
  changedBy(member: MemberId): Promise<ReadonlyMap<PushTopic, boolean>>;
  /** Saves every switch. */
  save(member: MemberId, settings: PushSettings): Promise<void>;
}

/** Which members' daily push has been handled, day by day. */
export interface DailyPushStore {
  /**
   * Of these candidates, those with the daily push switched on (with a phone or not) and their
   * day not handled yet, each with when their last day was handled.
   */
  due(candidates: readonly DailyCandidate[]): Promise<DuePush[]>;
  /**
   * Marks the member's day handled `at` that moment, `quiet` when there was nothing to send. False
   * when it already was, so a day is only ever handled once, however many runs reach it at once.
   */
  claim(handled: {
    readonly member: MemberId;
    readonly day: LocalDay;
    readonly quiet: boolean;
    readonly at: Date;
  }): Promise<boolean>;
}

/** Where the daily push's settings for everyone are kept: one value, and a log of every change. */
export interface DailyPushSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<DailyPushSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: DailyPushSettings, by: MemberId): Promise<boolean>;
}

/** Where the teammate push's settings for everyone are kept: one value, and a log of every change. */
export interface TeammatePushSettingsStore {
  /**
   * The settings now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<TeammatePushSettings>;
  /**
   * Saves `settings` with `by` as who changed them, unless they are the settings already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(settings: TeammatePushSettings, by: MemberId): Promise<boolean>;
}

/** How a teammate push goes to a member: ringing, or silently once their rings are used up. */
export type TeammatePushRing = 'ring' | 'silent';

/** Which teammate pushes have been handled, check-in by check-in and member by member. */
export interface TeammatePushStore {
  /**
   * Marks the push about `checkIn` to `member` handled `at` that moment, and says how it goes:
   * `ring` while fewer than `dailyRings` rang for the member in the 24 hours before, else
   * `silent`. Undefined when it already was handled, and then it must not be sent again.
   */
  claim(handled: {
    readonly checkIn: string;
    readonly member: MemberId;
    readonly at: Date;
    readonly dailyRings: number;
  }): Promise<TeammatePushRing | undefined>;
}
