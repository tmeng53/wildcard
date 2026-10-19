import type { CheckInId, CheckInRecord, MemberId, SquadId } from './domain/check-in.js';
import type { DayRange } from './domain/day-range.js';
import type { PhotoPath } from './domain/photos.js';
import type { Reaction, ReactionKind, ReactOutcome } from './domain/reaction.js';
import type { PlanDays, WeekStart } from './domain/weekly-plan.js';

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
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
}

/** Where reactions on check-ins are kept. */
export interface ReactionStore {
  /** Saves the member's reaction on a check-in, in place of any they left before. */
  save(
    checkIn: CheckInId,
    reaction: { readonly member: MemberId; readonly kind: ReactionKind; readonly reactedAt: Date },
  ): Promise<ReactOutcome>;
  /** Takes the member's reaction off a check-in, if there is one. */
  remove(checkIn: CheckInId, member: MemberId): Promise<void>;
  /** A check-in's reactions, oldest first. */
  list(checkIn: CheckInId): Promise<Reaction[]>;
}

/** Where uploaded photo files are kept. */
export interface PhotoFiles {
  /** Whether a photo has been uploaded to this path. */
  exists(path: PhotoPath): Promise<boolean>;
}

/** The current time. */
export type Clock = () => Date;

/** Where members' weekly plans are kept: a row only for each week the member changed. */
export interface WeeklyPlanStore {
  /** The member's plan saved for `weekStart` or, failing that, for the latest week before it. */
  latestFrom(
    member: MemberId,
    weekStart: WeekStart,
  ): Promise<{ readonly weekStart: WeekStart; readonly days: PlanDays } | undefined>;
  /** Saves the member's plan for a week, replacing any saved before. */
  save(plan: {
    readonly member: MemberId;
    readonly weekStart: WeekStart;
    readonly days: PlanDays;
  }): Promise<void>;
}

/**
 * The member's IANA time zone and when they joined, from their profile, or `undefined` before
 * they save one.
 */
export type MemberCalendar = (
  member: MemberId,
) => Promise<{ readonly timeZone: string; readonly joinedAt: Date } | undefined>;
