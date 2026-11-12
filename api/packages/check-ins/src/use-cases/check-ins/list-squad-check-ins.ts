import type { CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import type { Comment } from '../../domain/comment.js';
import type { DayRange } from '../../domain/day-range.js';
import { sharedSquads, type Reaction } from '../../domain/reaction.js';
import { SquadNotJoinedError } from '../../errors.js';
import type { CheckInStore, CommentStore, ReactionStore, SquadMembership } from '../../ports.js';

export interface ListSquadCheckInsInput {
  readonly viewer: MemberId;
  readonly squad: SquadId;
  readonly days: DayRange;
}

/** A check-in in a squad's feed, with what teammates left on it, oldest first. */
export interface SquadPost {
  readonly checkIn: CheckInRecord;
  readonly reactions: readonly Reaction[];
  readonly comments: readonly Comment[];
}

/**
 * A squad's feed for a range of days posted on (a 补打卡 shows on the day it was posted), newest
 * first, for one of its members, each with its reactions and
 * comments. Only posts (发布到动态: a check-in only recorded isn't in it, not even for its
 * author) from members still in the squad: leaving a squad takes your check-ins
 * out of it. Others' posts only from when the viewer (last) joined: what the squad posted before
 * isn't theirs to read (Tracy, 2026-11-11). Someone else's check-in shows only the squads the viewer is in among its audience,
 * and, as everywhere, only the responses of members of the squads the viewer sees it through.
 */
export async function listSquadCheckIns(
  {
    store,
    membership,
    reactions,
    comments,
  }: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
    readonly comments: CommentStore;
  },
  { viewer, squad, days }: ListSquadCheckInsInput,
): Promise<SquadPost[]> {
  const viewerSquads = await membership.squadIdsOf(viewer);
  if (!viewerSquads.has(squad)) throw new SquadNotJoinedError(squad);
  const [members, joined] = await Promise.all([
    membership.membersOf(squad),
    membership.joinedAt(viewer, squad),
  ]);
  const checkIns = (await store.listForSquad({ ...days, squad, members, by: 'postedDay' })).filter(
    (checkIn) =>
      checkIn.inFeed &&
      (checkIn.member === viewer || (joined !== undefined && checkIn.createdAt >= joined)),
  );
  const ids = checkIns.map(({ id }) => id);
  const [reactionsOf, commentsOf, squadsOfAuthor] = await Promise.all([
    reactions.listForAll(ids),
    comments.listForAll(ids),
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
      comments: (commentsOf.get(checkIn.id) ?? []).filter(visible),
    };
  });
}
