import { isReadableTimeZone, type MemberId, type Profile } from '../../domain/profile.js';
import { TimeZoneUnknownError } from '../../errors.js';
import type { ProfileStore } from '../../ports.js';

export interface SaveProfileInput {
  readonly member: MemberId;
  readonly profile: Profile;
}

/**
 * Creates the member's profile on their first save and replaces it after that, so the app can
 * repeat a save it isn't sure arrived. Throws `TimeZoneUnknownError` for a zone that doesn't exist,
 * in the database's zone list or the API's own.
 */
export async function saveProfile(
  deps: { readonly store: ProfileStore },
  { member, profile }: SaveProfileInput,
): Promise<Profile> {
  if (!isReadableTimeZone(profile.timeZone) || !(await deps.store.save(member, profile))) {
    throw new TimeZoneUnknownError(profile.timeZone);
  }
  return profile;
}
