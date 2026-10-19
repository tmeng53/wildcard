import type { DeviceToken, MemberId } from '../../domain/device.js';
import type { PushNotification } from '../../domain/notification.js';
import type { DeviceStore, PushSender } from '../../ports.js';

/** What notifying did, device by device. */
export interface NotifyOutcome {
  readonly sent: number;
  /** Devices that no longer exist; they are forgotten. */
  readonly gone: number;
  /** Devices not sent to because sending isn't set up (no APNs key yet). */
  readonly off: number;
  /** Why each failed device failed. Nothing is retried. */
  readonly failures: readonly unknown[];
}

/**
 * Sends one notification to every phone of these members, all at once. A dead token is
 * forgotten; one device failing never stops the others.
 */
export async function notifyMembers(
  { store, sender }: { readonly store: DeviceStore; readonly sender: PushSender },
  {
    members,
    notification,
  }: {
    readonly members: readonly MemberId[];
    readonly notification: PushNotification;
  },
): Promise<NotifyOutcome> {
  if (members.length === 0) return { sent: 0, gone: 0, off: 0, failures: [] };
  const devices = await store.devicesOf(members);
  const results = await Promise.allSettled(
    devices.map((device) => sender.send(device, notification)),
  );
  const gone: DeviceToken[] = [];
  const failures: unknown[] = [];
  let sent = 0;
  let off = 0;
  results.forEach((result, index) => {
    if (result.status === 'rejected') failures.push(result.reason);
    else if (result.value === 'sent') sent += 1;
    else if (result.value === 'off') off += 1;
    else {
      const device = devices[index];
      if (device !== undefined) gone.push(device.token);
    }
  });
  if (gone.length > 0) await store.remove(gone);
  return { sent, gone: gone.length, off, failures };
}
