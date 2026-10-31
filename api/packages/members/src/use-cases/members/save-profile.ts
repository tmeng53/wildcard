import type { MemberId, Profile, ProfileSave } from '../../domain/profile.js';
import { TimeZoneUnknownError } from '../../errors.js';
import type { ProfileStore } from '../../ports.js';

export interface SaveProfileInput {
  readonly member: MemberId;
  readonly profile: ProfileSave;
}

/** Whether this runtime's time zone data knows the zone, so the API can read days in it. */
function runtimeKnows(timeZone: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone });
    return true;
  } catch {
    return false;
  }
}

/**
 * Creates the member's profile on their first save and replaces it after that, so the app can
 * repeat a save it isn't sure arrived. A number left out keeps the saved one, which the profile
 * returned carries. Throws `TimeZoneUnknownError` for a zone that doesn't
 * exist, in Postgres or in this runtime (Postgres also knows names like `posix/...`).
 */
export async function saveProfile(
  deps: { readonly store: ProfileStore },
  { member, profile }: SaveProfileInput,
): Promise<Profile> {
  if (!runtimeKnows(profile.timeZone) || !(await deps.store.save(member, profile))) {
    throw new TimeZoneUnknownError(profile.timeZone);
  }
  const { jerseyNumber } = profile;
  if (jerseyNumber !== undefined) return { ...profile, jerseyNumber };
  return (await deps.store.find(member)) ?? { ...profile, jerseyNumber: null };
}
