import type { Device, DeviceToken, MemberId } from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import type { DeviceStore, PushSender } from '../ports.js';
import { notifyMembers, type NotifyOutcome } from './push/notify-members.js';
import { registerDevice } from './push/register-device.js';
import { unregisterDevice } from './push/unregister-device.js';

/** Push notifications: the phones members get them on, and sending them. */
export interface Push {
  registerDevice(input: { readonly member: MemberId; readonly device: Device }): Promise<void>;
  unregisterDevice(input: {
    readonly member: MemberId;
    readonly token: DeviceToken;
  }): Promise<void>;
  notifyMembers(input: {
    readonly members: readonly MemberId[];
    readonly notification: PushNotification;
  }): Promise<NotifyOutcome>;
}

export function createPush(deps: {
  readonly store: DeviceStore;
  readonly sender: PushSender;
}): Push {
  return {
    registerDevice: (input) => registerDevice(deps, input),
    unregisterDevice: (input) => unregisterDevice(deps, input),
    notifyMembers: (input) => notifyMembers(deps, input),
  };
}
