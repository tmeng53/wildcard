import type { DailyCandidate, DuePush, LocalDay } from '../domain/daily.js';
import type { DailyPushSettings } from '../domain/daily-push-settings.js';
import type { Device, DeviceToken, MemberId } from '../domain/device.js';
import type { PushNotification } from '../domain/notification.js';
import type { PushSettings, PushSettingsChange } from '../domain/topic.js';
import type {
  DailyPushSettingsStore,
  DailyPushStore,
  DeviceStore,
  PushSender,
  SettingsStore,
} from '../ports.js';
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
    /** The switches to change; one left out keeps what it was (an older app knows fewer). */
    readonly settings: PushSettingsChange;
  }): Promise<PushSettings>;
  /**
   * Of these members, each on their own today, those whose daily push is due: they haven't
   * turned it off and today's hasn't been handled. A member without a phone is due too, so the
   * push is kept in their 通知 though it reaches no phone.
   */
  dailyDue(candidates: readonly DailyCandidate[]): Promise<DuePush[]>;
  /** Whether the daily push goes out at all, and at which hour on members' clocks. */
  dailySettings(): Promise<DailyPushSettings>;
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
  readonly dailySettings: DailyPushSettingsStore;
  readonly sender: PushSender;
}): Push {
  return {
    registerDevice: (input) => registerDevice(deps, input),
    unregisterDevice: (input) => unregisterDevice(deps, input),
    notifyMembers: (input) => notifyMembers(deps, input),
    settingsOf: (member) => pushSettings(deps, member),
    saveSettings: async ({ member, settings }) => {
      const merged = { ...(await pushSettings(deps, member)), ...settings };
      await deps.settings.save(member, merged);
      return merged;
    },
    dailyDue: (candidates) => deps.daily.due(candidates),
    dailySettings: () => deps.dailySettings.current(),
    claimDaily: (handled) => deps.daily.claim(handled),
  };
}
