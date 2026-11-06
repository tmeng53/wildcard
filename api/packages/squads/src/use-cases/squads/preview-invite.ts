import type { InviteCode } from '../../domain/invite-code.js';
import {
  isMemberOf,
  SQUAD_MEMBER_LIMIT,
  type MemberId,
  type Squad,
  type SquadName,
} from '../../domain/squad.js';
import { DEFAULT_DAYS_PER_MEMBER, type DaysPerMember } from '../../domain/weekly-goal.js';
import { InviteCodeUnknownError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';

/** The squad an invite belongs to, before joining. */
interface InviteSummary {
  readonly name: SquadName;
  readonly memberCount: number;
  readonly full: boolean;
  /** The squad's weekly goal (人均 N 天) as its captain last set it: what a new member joins. */
  readonly daysPerMember: DaysPerMember;
}

/**
 * What the web invite page shows anyone holding an invite: the squad, and its members, the
 * earliest to join first, for the page to show their characters. The ids are for looking those
 * up; the page is never sent anything that says who is in it.
 */
export interface PublicInvitePreview extends InviteSummary {
  readonly members: readonly MemberId[];
}

/**
 * What a signed-in member holding an invite sees before joining: the same as the web page, so
 * the join screen can show the squad's characters too, and whether they are in it already.
 */
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
  return { ...(await withMembers(store, squad)), joined: isMemberOf(squad, viewer) };
}

/** The squad an invite code belongs to, as the web invite page shows it to anyone. */
export async function previewPublicInvite(
  { store }: { readonly store: SquadStore },
  inviteCode: InviteCode,
): Promise<PublicInvitePreview> {
  const squad = await store.findByInviteCode(inviteCode);
  if (squad === undefined) throw new InviteCodeUnknownError();
  return withMembers(store, squad);
}

async function withMembers(store: SquadStore, squad: Squad): Promise<PublicInvitePreview> {
  return { ...(await summary(store, squad)), members: squad.members.map(({ member }) => member) };
}

async function summary(store: SquadStore, squad: Squad): Promise<InviteSummary> {
  const goals = await store.weeklyGoals(squad.id);
  return {
    name: squad.name,
    memberCount: squad.members.length,
    full: squad.members.length >= SQUAD_MEMBER_LIMIT,
    daysPerMember: goals.at(-1)?.daysPerMember ?? DEFAULT_DAYS_PER_MEMBER,
  };
}
