import type { DailyCandidate, DuePush, LocalDay } from '../domain/daily.js';
import type { Device, DeviceToken, MemberId } from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import type { PushSettings } from '../domain/topic.js';
import type { DailyPushStore, DeviceStore, PushSender, SettingsStore } from '../ports.js';
import { notifyMembers, type NotifyOutcome } from './push/notify-members.js';
import { pushSettings } from './push/push-settings.js';
import { registerDevice } from './push/register-device.js';
import { unregisterDevice } from './push/unregister-device.js';

/**
 * Push notifications: the phones members get them on, the switches that turn each kind off, and
 * sending them.
 */
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
  /** The member's switches, every kind of push on until they turn it off. */
  settingsOf(member: MemberId): Promise<PushSettings>;
  saveSettings(input: {
    readonly member: MemberId;
    readonly settings: PushSettings;
  }): Promise<PushSettings>;
  /**
   * Of these members, each on their own today, those whose daily push is due: they have a phone,
   * haven't turned it off, and today's hasn't been handled.
   */
  dailyDue(candidates: readonly DailyCandidate[]): Promise<DuePush[]>;
  /**
   * Marks the member's daily push for `day` handled `at` that moment, `quiet` when there's nothing
   * to send. False when another run already did, and then this one must not send it.
   */
  claimDaily(input: {
    readonly member: MemberId;
    readonly day: LocalDay;
    readonly quiet: boolean;
    readonly at: Date;
  }): Promise<boolean>;
}

export function createPush(deps: {
  readonly store: DeviceStore;
  readonly settings: SettingsStore;
  readonly daily: DailyPushStore;
  readonly sender: PushSender;
}): Push {
  return {
    registerDevice: (input) => registerDevice(deps, input),
    unregisterDevice: (input) => unregisterDevice(deps, input),
    notifyMembers: (input) => notifyMembers(deps, input),
    settingsOf: (member) => pushSettings(deps, member),
    saveSettings: async ({ member, settings }) => {
      await deps.settings.save(member, settings);
      return settings;
    },
    dailyDue: (candidates) => deps.daily.due(candidates),
    claimDaily: (handled) => deps.daily.claim(handled),
  };
}
