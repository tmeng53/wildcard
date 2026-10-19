import type { CheckInId, CheckInRecord, MemberId, SquadId } from './domain/check-in.js';
import type { DayRange } from './domain/day-range.js';

/** What saving a new check-in did. Uniqueness is the database's to decide, so two saves at once can't both pass. */
export type InsertOutcome =
  { readonly saved: true } | { readonly saved: false; readonly taken: 'id' | 'dailyDisclaimer' };

/** Where check-ins and squad memberships are kept. */
export interface CheckInStore {
  /** The check-in saved under `id`, whoever made it. */
  find(id: CheckInId): Promise<CheckInRecord | undefined>;
  /** Saves a new check-in with its audience, or says which uniqueness rule stopped it. */
  insert(checkIn: CheckInRecord): Promise<InsertOutcome>;
  /** The squads `member` is in now. */
  squadsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /**
   * Check-ins sent to `squad` from members still in it, newest day first, with their whole
   * audience.
   */
  listForSquad(query: DayRange & { readonly squad: SquadId }): Promise<CheckInRecord[]>;
  /** A member's own check-ins, newest day first. */
  listForMember(query: DayRange & { readonly member: MemberId }): Promise<CheckInRecord[]>;
}

/** The current time. */
export type Clock = () => Date;
