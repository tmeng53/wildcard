import type { Device, DeviceToken, MemberId } from './domain/device.js';
import type { PushNotification } from './domain/notification.js';

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
