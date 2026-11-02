import type { MemberId, SquadId } from '../../domain/check-in.js';
import { sharedSquads } from '../../domain/reaction.js';
import type { SquadMembership } from '../../ports.js';

/**
 * Who responded to the member's check-ins in `[since, until)` (reacted, or commented), from
 * `receivedBy`: each teammate once, however many check-ins they responded to. A response counts
 * only while its author and the member still share a squad the check-in went to, as in the
 * responses the member sees.
 */
export async function responsesReceived(
  {
    membership,
    receivedBy,
  }: {
    readonly membership: SquadMembership;
    readonly receivedBy: (query: {
      readonly member: MemberId;
      readonly since: Date;
      readonly until: Date;
    }) => Promise<readonly { readonly member: MemberId; readonly audience: readonly SquadId[] }[]>;
  },
  {
    member,
    since,
    until,
  }: { readonly member: MemberId; readonly since: Date; readonly until: Date },
): Promise<ReadonlySet<MemberId>> {
  const [received, squads] = await Promise.all([
    receivedBy({ member, since, until }),
    membership.squadIdsOf(member),
  ]);
  if (received.length === 0) return new Set();
  const membersOf = new Map<SquadId, ReadonlySet<MemberId>>(
    await Promise.all(
      [...squads].map(
        async (squad) => [squad, new Set(await membership.membersOf(squad))] as const,
      ),
    ),
  );
  const people = new Set<MemberId>();
  for (const { member: from, audience } of received) {
    // The member is the author, so they see it through the squads it went to that they're in.
    const through = sharedSquads({ audience }, { viewerSquads: squads, authorSquads: squads });
    if (!through.some((squad) => membersOf.get(squad)?.has(from) === true)) continue;
    people.add(from);
  }
  return people;
}
