import type { EquippedTitle, MemberId, Profile, ProfileSave, Squadmate } from './domain/profile.js';

/** Where members' profiles are kept. */
export interface ProfileStore {
  /** The member's profile, if they have saved one. */
  find(member: MemberId): Promise<Profile | undefined>;
  /**
   * Creates or replaces the member's profile, keeping the saved number when the save leaves it
   * out, in the same statement. Returns `false` when the store doesn't know the time zone.
   */
  save(member: MemberId, profile: ProfileSave): Promise<boolean>;
  /** What squadmates see of these members, by member. Members without a profile are left out. */
  squadmates(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, Squadmate>>;
  /**
   * Saves the title the member wears (null for none), logged with the rest of the profile;
   * nothing is saved or logged when it is the one worn already. Returns `false` when the member
   * has no profile.
   */
  equipTitle(member: MemberId, title: EquippedTitle | null): Promise<boolean>;
  /** When the member first saved their profile, right after signing up. */
  joinedAt(member: MemberId): Promise<Date | undefined>;
  /**
   * Members whose local time at `now` is `hour` o'clock (and `minute` past it, 0 if left out)
   * or later on the same calendar day, only on that ISO weekday (1 is Monday, 7 Sunday) when
   * `isoWeekday` is given, each with that day (`YYYY-MM-DD`) and when their clock read that time
   * the day before.
   */
  pastLocalHour(input: LocalTimeQuery): Promise<PastLocalHour[]>;
}

/** A time on every member's own clock, and the moment it is asked about. */
export interface LocalTimeQuery {
  readonly hour: number;
  readonly minute?: number;
  readonly isoWeekday?: number;
  readonly now: Date;
}

/** A member past a local hour today. */
export interface PastLocalHour {
  readonly member: MemberId;
  /** Their local day, `YYYY-MM-DD`. */
  readonly day: string;
  /** When their clock read the hour (and minute) the day before. */
  readonly hourTheDayBefore: Date;
}
