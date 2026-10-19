import type { InviteCode } from '../../domain/invite-code.js';
import {
  isMemberOf,
  SQUAD_MEMBER_LIMIT,
  type MemberId,
  type SquadName,
} from '../../domain/squad.js';
import { InviteCodeUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';

/** What someone holding an invite sees before joining: no ids, no other members' details. */
export interface InvitePreview {
  readonly name: SquadName;
  readonly memberCount: number;
  readonly full: boolean;
  /** True when the viewer is in the squad already. */
  readonly joined: boolean;
}

/** The squad an invite code belongs to, as the join screen shows it. */
export async function previewInvite(
  { store }: { readonly store: SquadStore },
  { inviteCode, viewer }: { readonly inviteCode: InviteCode; readonly viewer: MemberId },
): Promise<InvitePreview> {
  const squad = await store.findByInviteCode(inviteCode);
  if (squad === undefined) throw new InviteCodeUnknownError();
  return {
    name: squad.name,
    memberCount: squad.members.length,
    full: squad.members.length >= SQUAD_MEMBER_LIMIT,
    joined: isMemberOf(squad, viewer),
  };
}
