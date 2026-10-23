import type { InviteCode } from './domain/invite-code.js';
import type { Scene, ScenePick, SceneWeek } from './domain/scene.js';
import type { MemberId, Squad, SquadId, SquadName } from './domain/squad.js';

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
 * The week a squad picks its scene for at `moment`: from Sunday 8pm Eastern, when a week's
 * awards are given, it is the next week, so the crown winner picks the week after the one they
 * won.
 */
export type SceneWeekAt = (moment: Date) => SceneWeek;

/** What a captain's change did. `notCaptain`: the actor isn't the captain now. */
export type CaptainOutcome = 'changed' | 'unchanged' | 'notCaptain' | 'notMember';

/** What picking a scene did. `taken`: the week has a pick already. */
export type PickOutcome = 'picked' | 'taken';

/** What joining a squad did. `ended`: everyone left it, so its invite no longer works. */
export type JoinOutcome = 'joined' | 'alreadyMember' | 'squadFull' | 'squadLimit' | 'ended';

/** Where squads and their members are kept. */
export interface SquadStore {
  find(id: SquadId): Promise<Squad | undefined>;
  /** The squad with this invite code, unless it ended: everyone left it. */
  findByInviteCode(code: InviteCode): Promise<Squad | undefined>;
  /** The squads `member` is in now, the earliest joined first. */
  squadsOf(member: MemberId): Promise<Squad[]>;
  /** The ids of the squads `member` is in now. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in `squad` now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
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
