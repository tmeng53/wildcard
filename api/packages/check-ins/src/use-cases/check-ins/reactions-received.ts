import type { MemberId, SquadId } from '../../domain/check-in.js';
import { sharedSquads, type ReactionKind } from '../../domain/reaction.js';
import type { ReactionStore, SquadMembership } from '../../ports.js';

/**
 * Who reacted to the member's check-ins in `[since, until)`, by kind: each teammate once per
 * kind, however many check-ins they reacted to. A reaction counts only while its author and the
 * member still share a squad the check-in went to, as in the reactions the member sees.
 */
export async function reactionsReceived(
  {
    membership,
    reactions,
  }: { readonly membership: SquadMembership; readonly reactions: ReactionStore },
  {
    member,
    since,
    until,
  }: { readonly member: MemberId; readonly since: Date; readonly until: Date },
): Promise<ReadonlyMap<ReactionKind, ReadonlySet<MemberId>>> {
  const [received, squads] = await Promise.all([
    reactions.receivedBy({ member, since, until }),
    membership.squadIdsOf(member),
  ]);
  if (received.length === 0) return new Map();
  const membersOf = new Map<SquadId, ReadonlySet<MemberId>>(
    await Promise.all(
      [...squads].map(
        async (squad) => [squad, new Set(await membership.membersOf(squad))] as const,
      ),
    ),
  );
  const byKind = new Map<ReactionKind, Set<MemberId>>();
  for (const { member: from, kind, audience } of received) {
    // The member is the author, so they see it through the squads it went to that they're in.
    const through = sharedSquads({ audience }, { viewerSquads: squads, authorSquads: squads });
    if (!through.some((squad) => membersOf.get(squad)?.has(from) === true)) continue;
    const people = byKind.get(kind) ?? new Set<MemberId>();
    people.add(from);
    byKind.set(kind, people);
  }
  return byKind;
}
