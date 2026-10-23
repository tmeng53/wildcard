import type { CheckInId, CheckInRecord, MemberId, SquadId } from './domain/check-in.js';
import type { CheckInTotals } from './domain/totals.js';
import type { DayRange } from './domain/day-range.js';
import type { PhotoPath } from './domain/photos.js';
import type { Emoji, Reaction, SaveOutcome } from './domain/reaction.js';
import type { FuelGoals } from './domain/fuel-goal.js';
import type { PlanDays, WeekStart } from './domain/weekly-plan.js';

/** What saving a new check-in did. Uniqueness is the database's to decide, so two saves at once can't both pass. */
export type InsertOutcome =
  | { readonly saved: true }
  | { readonly saved: false; readonly taken: 'id' | 'dailyDisclaimer' | 'photo' };

/** Where check-ins are kept. */
export interface CheckInStore {
  /** The check-in saved under `id`, whoever made it. */
  find(id: CheckInId): Promise<CheckInRecord | undefined>;
  /** Saves a new check-in with its audience and photos, or says which uniqueness rule stopped it. */
  insert(checkIn: CheckInRecord): Promise<InsertOutcome>;
  /** Everything `member` ever checked in, counted by kind. */
  totals(member: MemberId): Promise<CheckInTotals>;
  /** Check-ins sent to `squad` from these members, newest day first, with their whole audience. */
  listForSquad(
    query: DayRange & { readonly squad: SquadId; readonly members: readonly MemberId[] },
  ): Promise<CheckInRecord[]>;
  /**
   * Squads that got a check-in for a day from `from` to `to` made before `before`, from anyone,
   * each once.
   */
  squadsCheckedInto(query: DayRange & { readonly before: Date }): Promise<SquadId[]>;
  /** A member's own check-ins, newest day first. */
  listForMember(query: DayRange & { readonly member: MemberId }): Promise<CheckInRecord[]>;
}

/** Who is in which squad now. The squads module keeps that; check-ins only ask. */
export interface SquadMembership {
  /** The squads `member` is in now. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in `squad` now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
}

/** Where reactions on check-ins are kept. */
export interface ReactionStore {
  /** Saves the member's reaction on a check-in, in place of any they left before. */
  save(
    checkIn: CheckInId,
    reaction: { readonly member: MemberId; readonly emoji: Emoji; readonly reactedAt: Date },
  ): Promise<SaveOutcome>;
  /** Takes the member's reaction off a check-in, if there is one. */
  remove(checkIn: CheckInId, member: MemberId): Promise<void>;
  /** A check-in's reactions, oldest first. */
  list(checkIn: CheckInId): Promise<Reaction[]>;
  /** The reactions on each of these check-ins, oldest first; a check-in without any is left out. */
  listForAll(checkIns: readonly CheckInId[]): Promise<Map<CheckInId, Reaction[]>>;
  /**
   * Reactions left in `[since, until)` on any of the member's check-ins, oldest first, each with
   * the squads that check-in went to.
   */
  receivedBy(query: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<(Reaction & { readonly audience: readonly SquadId[] })[]>;
}

/** Where uploaded photo files are kept. */
export interface PhotoFiles {
  /** Whether a photo has been uploaded to this path. */
  exists(path: PhotoPath): Promise<boolean>;
}

/** The current time. */
export type Clock = () => Date;

/**
 * Where members' weekly plans and 饮食小目标 are kept: a row only for each week the member
 * changed.
 */
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
  /** The member's 饮食小目标 saved for `weekStart`; goals don't carry over to later weeks. */
  fuelGoals(member: MemberId, weekStart: WeekStart): Promise<FuelGoals | undefined>;
  /** Saves the member's 饮食小目标 for a week, replacing any saved before. */
  saveFuelGoals(goals: {
    readonly member: MemberId;
    readonly weekStart: WeekStart;
    readonly goals: FuelGoals;
  }): Promise<void>;
}

/**
 * The member's IANA time zone and when they joined, from their profile, or `undefined` before
 * they save one.
 */
export type MemberCalendar = (
  member: MemberId,
) => Promise<{ readonly timeZone: string; readonly joinedAt: Date } | undefined>;
