import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../../domain/check-in.js';
import type { Comment } from '../../domain/comment.js';
import { weekOf } from '../../domain/days.js';
import type { Reaction } from '../../domain/reaction.js';
import { weekPagesOf, type WeekPages } from '../../domain/week-pages.js';
import { plannedTrainingDays, type WeekStart } from '../../domain/weekly-plan.js';
import type {
  CheckInStore,
  CommentStore,
  MemberCalendar,
  ReactionStore,
  WeeklyPlanStore,
} from '../../ports.js';
import { findWeeklyPlan } from '../weekly-plans.js';
import { zonesOf } from './member-zones.js';

/** A squad's week as it stood at a moment, for the week's awards and its 战报. */
export interface SquadWeekCheckIns {
  /** The members given, in that order, with their check-ins oldest first. */
  readonly members: readonly {
    readonly member: MemberId;
    readonly checkIns: readonly CheckInRecord[];
  }[];
  /** Reactions on those check-ins from those members; one without any is left out. */
  readonly reactions: ReadonlyMap<CheckInId, readonly Reaction[]>;
  /**
   * Comments on those check-ins written before the awards by those members, oldest first; one
   * without any is left out.
   */
  readonly comments: ReadonlyMap<CheckInId, readonly Comment[]>;
  /** The 战报's pages without AI, from these check-ins and the members' plans. */
  readonly pages: WeekPages;
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
 * A squad's week as it stood at `before`, for these members (who was in the squad then, in the
 * order they joined): their check-ins and the reactions and comments on them made before it, and the 战报's
 * pages from those and the members' plans. What the week's awards and its frozen 战报 are made
 * from; a check-in or reaction made later still counts for the week's summary, only not here.
 */
export async function squadWeekCheckIns(
  deps: {
    readonly store: CheckInStore;
    readonly reactions: ReactionStore;
    readonly plans: WeeklyPlanStore;
    readonly calendarOf: MemberCalendar;
    readonly comments: CommentStore;
  },
  {
    squad,
    weekStart,
    before,
    members: memberIds,
  }: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
    readonly before: Date;
    readonly members: readonly MemberId[];
  },
): Promise<SquadWeekCheckIns> {
  const week = weekOf(weekStart);
  const [first] = memberIds;
  // A squad has at most 8 members, so one plan read each is fine.
  const [plans, zones, listed] = await Promise.all([
    Promise.all(
      memberIds.map((member) => findWeeklyPlan({ store: deps.plans }, { member, weekStart })),
    ),
    first === undefined ? [] : zonesOf(deps.calendarOf, { members: memberIds, viewer: first }),
    memberIds.length === 0
      ? []
      : deps.store.listForSquad({ squad, members: memberIds, from: week.from, to: week.to }),
  ]);
  const checkIns = listed
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
    const counted = each.filter(
      ({ member, reactedAt }) => inSquad.has(member) && reactedAt < before,
    );
    if (counted.length > 0) reactions.set(checkIn, counted);
  }
  const comments = new Map<CheckInId, Comment[]>();
  for (const [checkIn, each] of allComments) {
    const fromSquad = each.filter(
      ({ member, commentedAt }) => inSquad.has(member) && commentedAt < before,
    );
    if (fromSquad.length > 0) comments.set(checkIn, fromSquad);
  }
  const members = memberIds.map((member, index) => ({
    member,
    plannedDays: plannedTrainingDays(plans[index]?.days ?? [], {
      weekDays: week.days,
      joinedOn: zones[index]?.joinedOn,
    }),
    checkIns: checkIns.filter((each) => each.member === member),
  }));
  const pages = weekPagesOf(
    { week, members, reactions },
    new Map(memberIds.map((member, index) => [member, plans[index]?.days ?? []])),
  );
  return {
    members: members.map(({ member, checkIns: theirs }) => ({ member, checkIns: theirs })),
    reactions,
    comments,
    pages,
  };
}
