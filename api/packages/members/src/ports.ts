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
  /** The catchphrases these members picked, by member. Members without one are left out. */
  catchphrases(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, string>>;
  /** When the member first saved their profile, right after signing up. */
  joinedAt(member: MemberId): Promise<Date | undefined>;
  /**
   * Members whose local time at `now` is `hour` o'clock or later on the same calendar day, each
   * with that day (`YYYY-MM-DD`).
   */
  pastLocalHour(input: {
    readonly hour: number;
    readonly now: Date;
  }): Promise<{ readonly member: MemberId; readonly day: string }[]>;
}
