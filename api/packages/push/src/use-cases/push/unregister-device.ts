import type { DeviceToken, MemberId } from '../../domain/device.js';
import type { DeviceStore } from '../../ports.js';

/**
 * Stops push notifications to one of the member's phones, when they sign out on it. A token that
 * isn't theirs (any more) is left alone, so this is safe to repeat.
 */
export function unregisterDevice(
  { store }: { readonly store: DeviceStore },
  { member, token }: { readonly member: MemberId; readonly token: DeviceToken },
): Promise<void> {
  return store.unregister(member, token);
}
