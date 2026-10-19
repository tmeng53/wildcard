import type { CheckInId, CheckInRecord, MemberId, SquadId } from './domain/check-in.js';
import type { DayRange } from './domain/day-range.js';
import type { PhotoPath } from './domain/photos.js';

/** What saving a new check-in did. Uniqueness is the database's to decide, so two saves at once can't both pass. */
export type InsertOutcome =
  | { readonly saved: true }
  | { readonly saved: false; readonly taken: 'id' | 'dailyDisclaimer' | 'photo' };

/** Where check-ins and squad memberships are kept. */
export interface CheckInStore {
  /** The check-in saved under `id`, whoever made it. */
  find(id: CheckInId): Promise<CheckInRecord | undefined>;
  /** Saves a new check-in with its audience and photos, or says which uniqueness rule stopped it. */
  insert(checkIn: CheckInRecord): Promise<InsertOutcome>;
  /** The squads `member` is in now. */
  squadsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in `squad` now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Days ever with a 练了 from `member`. Several 练了 on one day count once. */
  countTrainedDays(member: MemberId): Promise<number>;
  /**
   * Check-ins sent to `squad` from members still in it, newest day first, with their whole
   * audience.
   */
  listForSquad(query: DayRange & { readonly squad: SquadId }): Promise<CheckInRecord[]>;
  /** A member's own check-ins, newest day first. */
  listForMember(query: DayRange & { readonly member: MemberId }): Promise<CheckInRecord[]>;
}

/** Where uploaded photo files are kept. */
export interface PhotoFiles {
  /** Whether a photo has been uploaded to this path. */
  exists(path: PhotoPath): Promise<boolean>;
}

/** Each member's IANA time zone, which another module keeps. */
export interface MemberZones {
  /** The zones of those of `members` who have saved one. */
  timeZonesOf(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, string>>;
}

/** The current time. */
export type Clock = () => Date;
