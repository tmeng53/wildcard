import { MemberId as NoticeMember, SquadId as NoticeSquad, type Notices } from '@wildcard/notices';
import type { DisbandedSquad } from '@wildcard/squads';

import type { Log } from '../log.js';

// 解散小队 (Tracy, 2026-11-22): everyone the captain took out is told quietly in 通知, never by
// push, so the squad isn't simply gone the next time they open the app.

/**
 * Tells each member but the captain that the captain disbanded the squad. Never fails the
 * disband: a failure is logged.
 */
export async function tellDisbanded(
  deps: { readonly notices: Pick<Notices, 'tell'>; readonly log: Log },
  {
    squad,
    captain,
    disbanded,
  }: { readonly squad: string; readonly captain: string; readonly disbanded: DisbandedSquad },
): Promise<void> {
  const told = disbanded.members.filter((member) => member !== captain);
  if (told.length === 0) return;
  try {
    await deps.notices.tell(
      told.map((member) => ({
        member: NoticeMember.parse(member),
        squad: NoticeSquad.parse(squad),
        kind: 'squadDisbanded' as const,
        subject: { version: 1 as const, name: disbanded.name },
      })),
    );
  } catch (error) {
    deps.log.error('squad disbanding not told to its members', { squad, error });
  }
}
