import type { InviteCodes } from '../domain/invite-code.js';
import type { MemberId, Squad, SquadId } from '../domain/squad.js';
import type { SquadStore } from '../ports.js';
import { createSquad, type CreatedSquad, type CreateSquadInput } from './squads/create-squad.js';
import { findSquad } from './squads/find-squad.js';
import { joinSquad, type JoinedSquad, type JoinSquadInput } from './squads/join-squad.js';
import { previewInvite, type InvitePreview } from './squads/preview-invite.js';
import type { InviteCode } from '../domain/invite-code.js';

/** Squads: creating one, joining by invite code, leaving, and who is in each. */
export interface Squads {
  create(input: CreateSquadInput): Promise<CreatedSquad>;
  join(input: JoinSquadInput): Promise<JoinedSquad>;
  previewInvite(input: { inviteCode: InviteCode; viewer: MemberId }): Promise<InvitePreview>;
  find(input: { squad: SquadId; viewer: MemberId }): Promise<Squad>;
  /** The squads a member is in now, the earliest joined first. */
  listMine(member: MemberId): Promise<Squad[]>;
  /**
   * Takes the member out of the squad; nothing happens if they aren't in it. A squad is never
   * deleted, even when its last member leaves: check-ins sent to it still point at it.
   */
  leave(input: { squad: SquadId; member: MemberId }): Promise<void>;
}

export function createSquads(deps: {
  readonly store: SquadStore;
  readonly inviteCodes: InviteCodes;
}): Squads {
  return {
    create: (input) => createSquad(deps, input),
    join: (input) => joinSquad(deps, input),
    previewInvite: (input) => previewInvite(deps, input),
    find: (input) => findSquad(deps, input),
    listMine: (member) => deps.store.squadsOf(member),
    leave: ({ squad, member }) => deps.store.leave(squad, member),
  };
}
