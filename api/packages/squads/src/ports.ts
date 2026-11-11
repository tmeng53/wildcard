import type { ReaderLanguage } from '@wildcard/language-model';

import type { InviteCode } from './domain/invite-code.js';
import type { Scene, ScenePick, SceneWeek } from './domain/scene.js';
import type { MemberId, Squad, SquadId, SquadName } from './domain/squad.js';
import type { GoalSuggestion } from './domain/goal-suggestion.js';
import type { TimeZoneSetting } from './domain/time-zone.js';
import type { DaysPerMember, WeeklyGoalSetting } from './domain/weekly-goal.js';

/**
 * Whether the member has consented to the current AI terms. Being in a squad needs it: the
 * weekly awards send the squad's captions and 请假条 to the AI provider.
 */
export type AiConsentCheck = (member: MemberId) => Promise<boolean>;

export interface NewSquad {
  readonly id: SquadId;
  readonly name: SquadName;
  readonly inviteCode: InviteCode;
  readonly creator: MemberId;
  /** The squad's weekly goal, counting from the week it is made: the creator's week. */
  readonly goal: { readonly daysPerMember: DaysPerMember; readonly week: SceneWeek };
  /** The squad's time zone, counting from the squad's week now on that zone's own clock. */
  readonly timeZone: { readonly zone: string; readonly week: SceneWeek };
}

/**
 * What creating a squad did. The limits are checked where the write happens, so two requests at
 * once can't both pass them.
 */
export type CreateOutcome =
  | { readonly created: true }
  | { readonly created: false; readonly refused: 'idTaken' | 'inviteCodeTaken' | 'squadLimit' };

/**
 * The members who won last week's crown (皇冠), as the Sunday 战报 names them, in the order they
 * joined; empty when nobody did. `viewer` is a member of the squad asking.
 */
export type CrownHolders = (input: {
  readonly squad: SquadId;
  readonly week: SceneWeek;
  readonly viewer: MemberId;
}) => Promise<readonly MemberId[]>;

/**
 * The week a squad picks its scene for at `moment`: from Sunday 8pm on the squad's clock, when a week's
 * awards are given, it is the next week, so the crown winner picks the week after the one they
 * won.
 */
export type SceneWeekAt = (moment: Date, squad: SquadId) => Promise<SceneWeek>;

/** What a captain's change did. `notCaptain`: the actor isn't the captain now. */
export type CaptainOutcome = 'changed' | 'unchanged' | 'notCaptain' | 'notMember';

/** What picking a scene did. `taken`: the week has a pick already. */
export type PickOutcome = 'picked' | 'taken';

/** What joining a squad did. `ended`: everyone left it, so its invite no longer works. */
export type JoinOutcome = 'joined' | 'alreadyMember' | 'squadFull' | 'squadLimit' | 'ended';

/** How a member came out of the squad they were last in. */
export interface SquadExit {
  readonly squad: SquadId;
  readonly name: string;
  readonly how: 'left' | 'removed';
}

/** Where squads and their members are kept. */
export interface SquadStore {
  find(id: SquadId): Promise<Squad | undefined>;
  /** The squad with this invite code, unless it ended: everyone left it. */
  findByInviteCode(code: InviteCode): Promise<Squad | undefined>;
  /** The squads `member` is in now, the earliest joined first. */
  squadsOf(member: MemberId): Promise<Squad[]>;
  /**
   * The squad `member` was last in, when they are in none now and their last change of squad
   * took them out of one: how they went (`left` themselves or `removed` by its captain).
   */
  lastExit(member: MemberId): Promise<SquadExit | undefined>;
  /** The ids of the squads `member` is in now. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in `squad` now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
  /**
   * The members in `squad` at a moment, in the order they (last) joined, from its log of joins
   * and leaves: someone who joined later isn't, someone who left later is.
   */
  membersAt(squad: SquadId, moment: Date): Promise<MemberId[]>;
  /**
   * Saves a new squad with its creator as its first member, unless the id or invite code is
   * taken or the creator is already in `SQUADS_PER_MEMBER` squads.
   */
  create(squad: NewSquad): Promise<CreateOutcome>;
  /**
   * Adds `member` to the squad unless they are in it already, it has `SQUAD_MEMBER_LIMIT`
   * members, or they are in `SQUADS_PER_MEMBER` squads.
   */
  join(squad: SquadId, member: MemberId): Promise<JoinOutcome>;
  /**
   * Takes `member` out of the squad. Nothing happens if they aren't in it. A captain who leaves
   * hands the captaincy to the earliest member left.
   */
  leave(squad: SquadId, member: MemberId): Promise<void>;
  /** Renames the squad, if `actor` is its captain. */
  rename(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly name: SquadName;
  }): Promise<CaptainOutcome>;
  /** Makes `to` the captain, if `actor` is the captain and `to` is in the squad. */
  handCaptaincy(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly to: MemberId;
  }): Promise<CaptainOutcome>;
  /**
   * Takes `member` out of the squad, if `actor` is its captain; `unchanged` when they weren't in
   * it.
   */
  remove(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly member: MemberId;
  }): Promise<CaptainOutcome>;
  /**
   * The squad's weekly goal settings, the earliest week first, a week's later settings after its
   * earlier ones.
   */
  weeklyGoals(squad: SquadId): Promise<WeeklyGoalSetting[]>;
  /**
   * Sets the squad's weekly goal from `week` on, if `actor` is its captain; `unchanged` when that
   * week's goal is that already.
   */
  setWeeklyGoal(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly daysPerMember: DaysPerMember;
    readonly week: SceneWeek;
  }): Promise<CaptainOutcome>;
  /**
   * Each squad's time zone settings, the earliest week first, a week's later settings after its
   * earlier ones; a squad with none is left out.
   */
  timeZones(squads: readonly SquadId[]): Promise<ReadonlyMap<SquadId, TimeZoneSetting[]>>;
  /**
   * Sets the squad's time zone from `week` on, if `actor` is its captain; `unchanged` when that
   * week's zone is that already. Throws `SquadTimeZoneUnknownError` for a zone the database
   * doesn't know.
   */
  setTimeZone(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly timeZone: string;
    readonly week: SceneWeek;
  }): Promise<CaptainOutcome>;
  /** Each squad's language (小队语言), its newest setting; a squad that never set one is left out. */
  languages(squads: readonly SquadId[]): Promise<ReadonlyMap<SquadId, ReaderLanguage>>;
  /**
   * Sets the squad's language from now on, if `actor` is its captain; `unchanged` when it is that
   * already.
   */
  setLanguage(change: {
    readonly squad: SquadId;
    readonly actor: MemberId;
    readonly language: ReaderLanguage;
  }): Promise<CaptainOutcome>;
  /** The higher goals suggested to the squad's captains, the earliest week first. */
  goalSuggestions(squad: SquadId): Promise<GoalSuggestion[]>;
  /**
   * Keeps that `suggestion` was told to the squad's captain for its week, unless one already was
   * that week: `taken` then, so a rerun tells nobody twice.
   */
  suggestGoal(squad: SquadId, suggestion: GoalSuggestion): Promise<'suggested' | 'taken'>;
  /** The squad's scene picks, every week's, the earliest first. */
  scenePicks(squad: SquadId): Promise<ScenePick[]>;
  /** Saves the week's scene, unless the week has one already. */
  pickScene(input: {
    readonly squad: SquadId;
    readonly week: SceneWeek;
    readonly scene: Scene;
    readonly by: MemberId;
  }): Promise<PickOutcome>;
}
