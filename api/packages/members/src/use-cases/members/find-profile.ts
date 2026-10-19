import type { MemberId, Profile } from '../../domain/profile.js';
import type { ProfileStore } from '../../ports.js';

/** The member's profile, or `undefined` until they first save one (right after signing up). */
export function findProfile(
  deps: { readonly store: ProfileStore },
  member: MemberId,
): Promise<Profile | undefined> {
  return deps.store.find(member);
}
