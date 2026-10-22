import type { MemberId, Profile, Squadmate } from '../domain/profile.js';
import type { PastLocalHour, ProfileStore } from '../ports.js';
import { findProfile } from './members/find-profile.js';
import { saveProfile, type SaveProfileInput } from './members/save-profile.js';

/** Members' own settings: reading and saving a profile. */
export interface Members {
  findProfile(member: MemberId): Promise<Profile | undefined>;
  saveProfile(input: SaveProfileInput): Promise<Profile>;
  /**
   * What squadmates see of these members (catchphrase, nickname and look), by member. Members
   * who haven't saved a profile are left out.
   */
  squadmates(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, Squadmate>>;
  /** When the member joined (first saved their profile), or `undefined` before that. */
  joinedAt(member: MemberId): Promise<Date | undefined>;
  /**
   * Everyone whose own clock at `now` reads `hour` o'clock or later, before midnight, with their
   * local day (`YYYY-MM-DD`) and when their clock read `hour` o'clock the day before. Members who
   * haven't saved a time zone aren't on it.
   */
  pastLocalHour(input: { readonly hour: number; readonly now: Date }): Promise<PastLocalHour[]>;
}

export function createMembers(deps: { readonly store: ProfileStore }): Members {
  return {
    findProfile: (member) => findProfile(deps, member),
    saveProfile: (input) => saveProfile(deps, input),
    squadmates: (members) => deps.store.squadmates(members),
    joinedAt: (member) => deps.store.joinedAt(member),
    pastLocalHour: (input) => deps.store.pastLocalHour(input),
  };
}
