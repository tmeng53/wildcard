import type { InviteCode } from '../../domain/invite-code.js';
import {
  isMemberOf,
  SQUAD_MEMBER_LIMIT,
  type MemberId,
  type Squad,
  type SquadName,
} from '../../domain/squad.js';
import { InviteCodeUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';

/**
 * What anyone holding an invite may see, signed in or not: no ids, no members' details, nothing
 * that says who is in it.
 */
export interface PublicInvitePreview {
  readonly name: SquadName;
  readonly memberCount: number;
  readonly full: boolean;
}

/** What a signed-in member holding an invite sees before joining. */
export interface InvitePreview extends PublicInvitePreview {
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
  return { ...publicPart(squad), joined: isMemberOf(squad, viewer) };
}

/** The squad an invite code belongs to, as the web invite page shows it to anyone. */
export async function previewPublicInvite(
  { store }: { readonly store: SquadStore },
  inviteCode: InviteCode,
): Promise<PublicInvitePreview> {
  const squad = await store.findByInviteCode(inviteCode);
  if (squad === undefined) throw new InviteCodeUnknownError();
  return publicPart(squad);
}

function publicPart(squad: Squad): PublicInvitePreview {
  return {
    name: squad.name,
    memberCount: squad.members.length,
    full: squad.members.length >= SQUAD_MEMBER_LIMIT,
  };
}
