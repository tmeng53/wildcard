import type { MemberId, Profile } from './domain/profile.js';

/** Where members' profiles are kept. */
export interface ProfileStore {
  /** The member's profile, if they have saved one. */
  find(member: MemberId): Promise<Profile | undefined>;
  /**
   * Creates or replaces the member's profile. Returns `false` when the store doesn't know the
   * time zone.
   */
  save(member: MemberId, profile: Profile): Promise<boolean>;
}
