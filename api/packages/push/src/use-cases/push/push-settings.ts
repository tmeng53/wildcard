import type { MemberId } from '../../domain/device.js';
import { DEFAULT_PUSH_SETTINGS, type PushSettings } from '../../domain/topic.js';
import type { SettingsStore } from '../../ports.js';

/** A member's push switches: the ones they changed, every other one on. */
export async function pushSettings(
  { settings }: { readonly settings: SettingsStore },
  member: MemberId,
): Promise<PushSettings> {
  const changed = await settings.changedBy(member);
  return { ...DEFAULT_PUSH_SETTINGS, ...Object.fromEntries(changed) };
}
