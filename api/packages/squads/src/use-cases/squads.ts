import type { InviteCodes } from '../domain/invite-code.js';
import type { ScenePick, Scene, SceneWeek } from '../domain/scene.js';
import type { MemberId, Squad, SquadId, SquadName } from '../domain/squad.js';
import type { AiConsentCheck, PickOutcome, SquadStore } from '../ports.js';
import { createSquad, type CreatedSquad, type CreateSquadInput } from './squads/create-squad.js';
import { findSquad } from './squads/find-squad.js';
import { joinSquad, type JoinedSquad, type JoinSquadInput } from './squads/join-squad.js';
import {
  previewInvite,
  previewPublicInvite,
  type InvitePreview,
  type PublicInvitePreview,
} from './squads/preview-invite.js';
import type { InviteCode } from '../domain/invite-code.js';
import { handCaptaincy, removeMember, renameSquad } from './squads/settings.js';

/** Squads: creating one, joining by invite code, leaving, and who is in each. */
export interface Squads {
  create(input: CreateSquadInput): Promise<CreatedSquad>;
  join(input: JoinSquadInput): Promise<JoinedSquad>;
  previewInvite(input: { inviteCode: InviteCode; viewer: MemberId }): Promise<InvitePreview>;
  /** The squad as anyone holding its invite code may see it, signed in or not. */
  previewPublicInvite(inviteCode: InviteCode): Promise<PublicInvitePreview>;
  find(input: { squad: SquadId; viewer: MemberId }): Promise<Squad>;
  /** The squads a member is in now, the earliest joined first. */
  listMine(member: MemberId): Promise<Squad[]>;
  /** The ids of the squads a member is in now: what other modules ask instead of reading tables. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in a squad now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
  /** Everyone in any of these squads now, each once. */
  membersOfAny(squads: readonly SquadId[]): Promise<ReadonlySet<MemberId>>;
  /**
   * Takes the member out of the squad; nothing happens if they aren't in it. When the last member
   * leaves, the squad ends: its invite stops working, and it stays. A squad is deleted only with
   * the account of its last member.
   */
  leave(input: { squad: SquadId; member: MemberId }): Promise<void>;
  /** Renames the squad, for its captain. */
  rename(input: { squad: SquadId; member: MemberId; name: SquadName }): Promise<Squad>;
  /** Hands the captaincy to another member, for the captain. */
  handCaptaincy(input: { squad: SquadId; member: MemberId; to: MemberId }): Promise<Squad>;
  /**
   * Takes `removed` out of the squad: themselves (leaving), or anyone, for the captain. Safe to
   * repeat.
   */
  removeMember(input: { squad: SquadId; member: MemberId; removed: MemberId }): Promise<void>;
  /** The squad's scene picks, the earliest week first: for its scene (`createSquadScenes`). */
  scenePicks(squad: SquadId): Promise<ScenePick[]>;
  /** Saves a week's scene unless it has one: the rules are `createSquadScenes`'s. */
  savePick(input: {
    squad: SquadId;
    week: SceneWeek;
    scene: Scene;
    by: MemberId;
  }): Promise<PickOutcome>;
}

export function createSquads(deps: {
  readonly store: SquadStore;
  readonly inviteCodes: InviteCodes;
  readonly aiConsent: AiConsentCheck;
}): Squads {
  return {
    create: (input) => createSquad(deps, input),
    join: (input) => joinSquad(deps, input),
    previewInvite: (input) => previewInvite(deps, input),
    previewPublicInvite: (inviteCode) => previewPublicInvite(deps, inviteCode),
    find: (input) => findSquad(deps, input),
    listMine: (member) => deps.store.squadsOf(member),
    squadIdsOf: (member) => deps.store.squadIdsOf(member),
    membersOf: (squad) => deps.store.membersOf(squad),
    membersOfAny: (squads) => deps.store.membersOfAny(squads),
    leave: ({ squad, member }) => deps.store.leave(squad, member),
    rename: (input) => renameSquad(deps, input),
    handCaptaincy: (input) => handCaptaincy(deps, input),
    removeMember: (input) => removeMember(deps, input),
    scenePicks: (squad) => deps.store.scenePicks(squad),
    savePick: (input) => deps.store.pickScene(input),
  };
}
