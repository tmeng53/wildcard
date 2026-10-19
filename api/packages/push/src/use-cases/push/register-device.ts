import type { Device, MemberId } from '../../domain/device.js';
import type { DeviceStore } from '../../ports.js';

/**
 * Saves the phone a member gets push notifications on. The app registers on every launch, since
 * iOS may change the token; repeating it changes nothing, and a phone someone else signed out
 * of moves to the member signing in.
 */
export function registerDevice(
  { store }: { readonly store: DeviceStore },
  { member, device }: { readonly member: MemberId; readonly device: Device },
): Promise<void> {
  return store.register(member, device);
}
