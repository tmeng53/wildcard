import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import type { DayRange } from '../../domain/day-range.js';
import { withoutTakenBackDisclaimers } from '../../domain/days.js';
import { sharedSquads, type Reaction } from '../../domain/reaction.js';
import type { Reply } from '../../domain/reply.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, ReactionStore, ReplyStore, SquadMembership } from '../../ports.js';

export interface ListSquadCheckInsInput {
  readonly viewer: MemberId;
  readonly squad: SquadId;
  readonly days: DayRange;
}

/** A check-in in a squad's feed, with what teammates left on it, oldest first. */
export interface SquadPost {
  readonly checkIn: CheckInRecord;
  readonly reactions: readonly Reaction[];
  /** Always empty on anything but a 请假条. */
  readonly replies: readonly Reply[];
}

/**
 * A squad's check-ins for a range of days, for one of its members, each with its reactions and
 * replies. Only check-ins from members still in the squad: leaving a squad takes your check-ins
 * out of it. Someone else's check-in shows only the squads the viewer is in among its audience,
 * and, as everywhere, only the responses of members of the squads the viewer sees it through.
 * A 请假条 taken back by a 练了 the same day is left out.
 */
export async function listSquadCheckIns(
  {
    store,
    membership,
    reactions,
    replies,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
    readonly replies: ReplyStore;
  },
  { viewer, squad, days }: ListSquadCheckInsInput,
): Promise<SquadPost[]> {
  const viewerSquads = await membership.squadIdsOf(viewer);
  if (!viewerSquads.has(squad)) throw new SquadNotJoinedError(squad);
  const members = await membership.membersOf(squad);
  const checkIns = withoutTakenBackDisclaimers(
    await store.listForSquad({ ...days, squad, members }),
  );
  const ids = checkIns.map(({ id }) => id);
  const [reactionsOf, repliesOf, squadsOfAuthor] = await Promise.all([
    reactions.listForAll(ids),
    replies.listForAll(ids),
    Promise.all(
      members.map(async (member) => [member, await membership.squadIdsOf(member)] as const),
    ).then((pairs) => new Map(pairs)),
  ]);
  const throughOf = (checkIn: CheckInRecord) =>
    sharedSquads(checkIn, {
      viewerSquads,
      authorSquads: squadsOfAuthor.get(checkIn.member) ?? new Set(),
    });
  // Whose responses each check-in shows: the members of the squads it is seen through.
  const throughSquads = [...new Set(checkIns.flatMap(throughOf))];
  const membersOf = new Map(
    await Promise.all(
      throughSquads.map(async (each) => [each, new Set(await membership.membersOf(each))] as const),
    ),
  );
  return checkIns.map((checkIn) => {
    const through = throughOf(checkIn);
    const visible = ({ member }: { readonly member: MemberId }) =>
      through.some((each) => membersOf.get(each)?.has(member) === true);
    return {
      checkIn:
        checkIn.member === viewer
          ? checkIn
          : { ...checkIn, audience: checkIn.audience.filter((each) => viewerSquads.has(each)) },
      reactions: (reactionsOf.get(checkIn.id) ?? []).filter(visible),
      replies: (repliesOf.get(checkIn.id) ?? []).filter(visible),
    };
  });
}
