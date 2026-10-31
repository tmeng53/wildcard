import type { CheckInId, CheckInRecord, MemberId, SquadId } from './domain/check-in.js';
import type { CheckInTotals } from './domain/totals.js';
import type { DayRange } from './domain/day-range.js';
import type { CheckInKind, PostCursor } from './domain/post-cursor.js';
import type { PhotoPath } from './domain/photos.js';
import type { Comment, CommentId } from './domain/comment.js';
import type { Emoji, Reaction, SaveOutcome } from './domain/reaction.js';
import type { FuelGoals } from './domain/fuel-goal.js';
import type { PlanDays, WeekStart } from './domain/weekly-plan.js';
import type { WeekSummaryWords } from './domain/week-summary-words.js';

/** What saving a new check-in did. Uniqueness is the database's to decide, so two saves at once can't both pass. */
export type InsertOutcome =
  { readonly saved: true } | { readonly saved: false; readonly taken: 'id' | 'photo' };

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
  /**
   * Up to `limit` of a member's own check-ins, newest day first, then newest made, then by id
   * from the end: those after `after` when given, of one kind when given.
   */
  pageForMember(query: {
    readonly member: MemberId;
    readonly kind?: CheckInKind | undefined;
    readonly after?: PostCursor | undefined;
    readonly limit: number;
  }): Promise<CheckInRecord[]>;
  /** How many check-ins `member` ever made, of every kind. */
  countForMember(member: MemberId): Promise<number>;
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

/** The sports list. The sports module keeps it; check-ins only ask whether a sport is in it. */
export interface SportList {
  /** Whether `id` names a listed sport (`custom` never does). */
  isListed(id: string): Promise<boolean>;
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

/** What writing a comment did: saved it, found it saved already, or found its id holding another. */
export type CommentWriteOutcome = 'created' | 'unchanged' | 'conflict';

/** Where comments on check-ins are kept. A comment is never changed once written. */
export interface CommentStore {
  /**
   * Saves a new comment on a check-in. Says `unchanged` when the id holds this very comment
   * already and `conflict` when it holds another, saving nothing either way.
   */
  insert(checkIn: CheckInId, comment: Comment): Promise<CommentWriteOutcome>;
  /** The comment saved under `id`, with the check-in it is on. */
  find(id: CommentId): Promise<(Comment & { readonly checkIn: CheckInId }) | undefined>;
  /** Deletes a comment, if it is there. */
  remove(id: CommentId): Promise<void>;
  /** A check-in's comments, oldest first. */
  list(checkIn: CheckInId): Promise<Comment[]>;
  /** The comments on each of these check-ins, oldest first; a check-in without any is left out. */
  listForAll(checkIns: readonly CheckInId[]): Promise<Map<CheckInId, Comment[]>>;
  /**
   * Comments written in `[since, until)` on any of the member's check-ins by someone else,
   * oldest first, each with the squads that check-in went to.
   */
  receivedBy(query: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<(Comment & { readonly audience: readonly SquadId[] })[]>;
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

/** Where the Sunday summary's words are kept: one value, and a log of every change to it. */
export interface WeekSummaryWordsStore {
  /**
   * The words now. `forUpdate` holds the row until the caller's transaction ends, so two
   * admins changing them at once apply one change after the other.
   */
  current(options?: { readonly forUpdate?: boolean }): Promise<WeekSummaryWords>;
  /**
   * Saves `words` with `by` as who changed them, unless they are the words already: then
   * nothing is saved or logged. Says whether anything changed.
   */
  save(words: WeekSummaryWords, by: MemberId): Promise<boolean>;
}
