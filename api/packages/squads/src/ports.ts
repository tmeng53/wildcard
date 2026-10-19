import type { InviteCode } from './domain/invite-code.js';
import type { MemberId, Squad, SquadId, SquadName } from './domain/squad.js';

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
