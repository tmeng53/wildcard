import type { MemberId } from '../../domain/check-in.js';
import type { ReactionKind } from '../../domain/reaction.js';
import type { CheckInStore, ReactionStore } from '../../ports.js';

/**
 * Who reacted to the member's check-ins in `[since, until)`, by kind: each teammate once per
 * kind, however many check-ins they reacted to. Only teammates in one of the member's squads
 * now count, as in the reactions the member sees.
 */
export async function reactionsReceived(
  { store, reactions }: { readonly store: CheckInStore; readonly reactions: ReactionStore },
  {
    member,
    since,
    until,
  }: { readonly member: MemberId; readonly since: Date; readonly until: Date },
): Promise<ReadonlyMap<ReactionKind, ReadonlySet<MemberId>>> {
  const [received, squads] = await Promise.all([
    reactions.receivedBy({ member, since, until }),
    store.squadsOf(member),
  ]);
  if (received.length === 0) return new Map();
  const teammates = await store.membersOfAny([...squads]);
  const byKind = new Map<ReactionKind, Set<MemberId>>();
  for (const { member: from, kind } of received) {
    if (!teammates.has(from)) continue;
    const people = byKind.get(kind) ?? new Set<MemberId>();
    people.add(from);
    byKind.set(kind, people);
  }
  return byKind;
}
