import type { InviteCode } from './domain/invite-code.js';
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

/** What joining a squad did. */
export type JoinOutcome = 'joined' | 'alreadyMember' | 'squadFull' | 'squadLimit';

/** Where squads and their members are kept. */
export interface SquadStore {
  find(id: SquadId): Promise<Squad | undefined>;
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
  /** Takes `member` out of the squad. Nothing happens if they aren't in it. */
  leave(squad: SquadId, member: MemberId): Promise<void>;
}
