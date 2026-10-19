import type { MemberId, Profile } from '../domain/profile.js';
import type { ProfileStore } from '../ports.js';
import { findProfile } from './members/find-profile.js';
import { saveProfile, type SaveProfileInput } from './members/save-profile.js';

/** Members' own settings: reading and saving a profile. */
export interface Members {
  findProfile(member: MemberId): Promise<Profile | undefined>;
  saveProfile(input: SaveProfileInput): Promise<Profile>;
  /**
   * The catchphrases these members picked, by member, for squadmates to see. Members who haven't
   * picked one are left out: the app uses their persona's own line.
   */
  catchphrasesOf(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, string>>;
  /** When the member joined (first saved their profile), or `undefined` before that. */
  joinedAt(member: MemberId): Promise<Date | undefined>;
  /**
   * Everyone whose own clock at `now` reads `hour` o'clock or later, before midnight, with their
   * local day (`YYYY-MM-DD`). Members who haven't saved a time zone aren't on it.
   */
  pastLocalHour(input: {
    readonly hour: number;
    readonly now: Date;
  }): Promise<{ readonly member: MemberId; readonly day: string }[]>;
}

export function createMembers(deps: { readonly store: ProfileStore }): Members {
  return {
    findProfile: (member) => findProfile(deps, member),
    saveProfile: (input) => saveProfile(deps, input),
    catchphrasesOf: (members) => deps.store.catchphrases(members),
    joinedAt: (member) => deps.store.joinedAt(member),
    pastLocalHour: (input) => deps.store.pastLocalHour(input),
  };
}
