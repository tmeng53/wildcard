import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import type { Comment } from '../../domain/comment.js';
import { weekOf } from '../../domain/days.js';
import type { Reaction } from '../../domain/reaction.js';
import type { WeekStart } from '../../domain/weekly-plan.js';
import type { CheckInStore, CommentStore, ReactionStore, SquadMembership } from '../../ports.js';

/** A squad's week as it stood at a moment, for the week's awards. */
export interface SquadWeekCheckIns {
  /** Everyone in the squad now, in the order they joined, with their check-ins oldest first. */
  readonly members: readonly {
    readonly member: MemberId;
    readonly checkIns: readonly CheckInRecord[];
  }[];
  /** Reactions on those check-ins from members of the squad now; one without any is left out. */
  readonly reactions: ReadonlyMap<CheckInId, readonly Reaction[]>;
  /**
   * Comments on those check-ins written before the awards by members of the squad now, oldest
   * first; one without any is left out.
   */
  readonly comments: ReadonlyMap<CheckInId, readonly Comment[]>;
}

/** The squads that got a check-in for a day of the week made before `before`. */
export function squadsCheckedInto(
  { store }: { readonly store: CheckInStore },
  { weekStart, before }: { readonly weekStart: WeekStart; readonly before: Date },
): Promise<SquadId[]> {
  const { from, to } = weekOf(weekStart);
  return store.squadsCheckedInto({ from, to, before });
}

/**
 * A squad's check-ins for the week made before `before`, from everyone in it now: what the
 * week's awards are written from. A check-in made later still counts for the week, only not for
 * its awards. Members who left take their check-ins with them, as in the squad's feed.
 */
export async function squadWeekCheckIns(
  deps: {
    readonly store: CheckInStore;
    readonly membership: SquadMembership;
    readonly reactions: ReactionStore;
    readonly comments: CommentStore;
  },
  {
    squad,
    weekStart,
    before,
  }: { readonly squad: SquadId; readonly weekStart: WeekStart; readonly before: Date },
): Promise<SquadWeekCheckIns> {
  const { from, to } = weekOf(weekStart);
  const memberIds = await deps.membership.membersOf(squad);
  const checkIns = (await deps.store.listForSquad({ squad, members: memberIds, from, to }))
    .filter(({ createdAt }) => createdAt < before)
    .toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  const inSquad = new Set(memberIds);
  const ids = checkIns.map(({ id }) => id);
  const [allReactions, allComments] = await Promise.all([
    deps.reactions.listForAll(ids),
    deps.comments.listForAll(ids),
  ]);
  const reactions = new Map<CheckInId, Reaction[]>();
  for (const [checkIn, each] of allReactions) {
    const fromSquad = each.filter(({ member }) => inSquad.has(member));
    if (fromSquad.length > 0) reactions.set(checkIn, fromSquad);
  }
  const comments = new Map<CheckInId, Comment[]>();
  for (const [checkIn, each] of allComments) {
    const fromSquad = each.filter(
      ({ member, commentedAt }) => inSquad.has(member) && commentedAt < before,
    );
    if (fromSquad.length > 0) comments.set(checkIn, fromSquad);
  }
  return {
    members: memberIds.map((member) => ({
      member,
      checkIns: checkIns.filter((each) => each.member === member),
    })),
    reactions,
    comments,
  };
}
