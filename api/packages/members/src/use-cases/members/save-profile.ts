import { isKnownTimeZone } from '@wildcard/time-zones';

import type { MemberId, Profile, ProfileSave } from '../../domain/profile.js';
import { TimeZoneUnknownError } from '../../errors.js';
import type { ProfileStore } from '../../ports.js';

export interface SaveProfileInput {
  readonly member: MemberId;
  readonly profile: ProfileSave;
}

/**
 * Creates the member's profile on their first save and replaces it after that, so the app can
 * repeat a save it isn't sure arrived. A number left out keeps the saved one, and the birthday is
 * kept too (`saveBirthday` changes it); the profile returned carries both. Throws `TimeZoneUnknownError` for a zone that doesn't
 * exist, in Postgres or in this runtime (Postgres also knows names like `posix/...`).
 */
export async function saveProfile(
  deps: { readonly store: ProfileStore },
  { member, profile }: SaveProfileInput,
): Promise<Profile> {
  if (!isKnownTimeZone(profile.timeZone) || !(await deps.store.save(member, profile))) {
    throw new TimeZoneUnknownError(profile.timeZone);
  }
  // Read back for what the save kept: the number when left out, and the birthday.
  return (
    (await deps.store.find(member)) ?? {
      ...profile,
      jerseyNumber: profile.jerseyNumber ?? null,
      birthday: null,
    }
  );
}
