import type { MemberId, Profile, Squadmate } from './domain/profile.js';

/** Where members' profiles are kept. */
export interface ProfileStore {
  /** The member's profile, if they have saved one. */
  find(member: MemberId): Promise<Profile | undefined>;
  /**
   * Creates or replaces the member's profile. Returns `false` when the store doesn't know the
   * time zone.
   */
  save(member: MemberId, profile: Profile): Promise<boolean>;
  /** What squadmates see of these members, by member. Members without a profile are left out. */
  squadmates(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, Squadmate>>;
  /** When the member first saved their profile, right after signing up. */
  joinedAt(member: MemberId): Promise<Date | undefined>;
}
