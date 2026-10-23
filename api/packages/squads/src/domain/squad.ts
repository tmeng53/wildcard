import { nameText } from '@wildcard/typed-text';
import { z } from 'zod';

import type { InviteCode } from './invite-code.js';

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/** A squad holds 1 to 8 members: a squad of one is fine, friends join later. */
export const SQUAD_MEMBER_LIMIT = 8;

/** A member is in at most 3 squads. The first app shows only one; the API allows three. */
export const SQUADS_PER_MEMBER = 3;

/** A squad's name, as its creator types it: trimmed, then 1 to 20 characters, on one line. */
export const SquadName = nameText({
  max: 20,
  description: 'Trimmed, then 1 to 20 characters as people see them, on one line.',
});
export type SquadName = z.infer<typeof SquadName>;

export interface SquadMember {
  readonly member: MemberId;
  readonly joinedAt: Date;
}

/** A squad and who is in it now, the earliest to join first. */
export interface Squad {
  readonly id: SquadId;
  readonly name: SquadName;
  readonly inviteCode: InviteCode;
  readonly createdAt: Date;
  /** Who made it; null once they delete their account. */
  readonly createdBy: MemberId | null;
  /**
   * The captain (队长), who renames the squad, removes members and hands the captaincy on: the
   * creator at first. When the captain leaves or deletes their account, the earliest member to
   * join takes over. Null only once everyone has left.
   */
  readonly captain: MemberId | null;
  readonly members: readonly SquadMember[];
}

/**
 * Who captains a squad, from its stored captain and its members, the earliest joined first: the
 * stored one while they are in it, else the earliest member.
 */
export function captainOf(
  stored: MemberId | null,
  members: readonly SquadMember[],
): MemberId | null {
  if (stored !== null && members.some(({ member }) => member === stored)) return stored;
  return members[0]?.member ?? null;
}

/** Whether `member` is in the squad now. */
export function isMemberOf(squad: Squad, member: MemberId): boolean {
  return squad.members.some((entry) => entry.member === member);
}
