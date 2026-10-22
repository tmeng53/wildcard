import type { DailyCandidate, DuePush, LocalDay } from './domain/daily.js';
import type { Device, DeviceToken, MemberId } from './domain/device.js';
import type { PushNotification } from './domain/notification.js';
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
   * Of these candidates, those with a phone, the daily push switched on and their day not handled
   * yet, each with when their last day was handled.
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
