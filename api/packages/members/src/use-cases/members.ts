import type { MemberId, Profile } from '../domain/profile.js';
import type { ProfileStore } from '../ports.js';
import { findProfile } from './members/find-profile.js';
import { saveProfile, type SaveProfileInput } from './members/save-profile.js';

/** Members' own settings: reading and saving a profile. */
export interface Members {
  findProfile(member: MemberId): Promise<Profile | undefined>;
  saveProfile(input: SaveProfileInput): Promise<Profile>;
}

export function createMembers(deps: { readonly store: ProfileStore }): Members {
  return {
    findProfile: (member) => findProfile(deps, member),
    saveProfile: (input) => saveProfile(deps, input),
  };
}
