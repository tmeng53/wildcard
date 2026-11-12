import type {
  CheckInEdit,
  CheckInId,
  CheckInRecord,
  MemberId,
  SquadId,
} from '../domain/check-in.js';
import type { DayRange, Unshared } from '../domain/day-range.js';
import type { CheckInTotals, TrainedCheckIn, TrainingDay } from '../domain/totals.js';
import type { PlanDays, WeekStart } from '../domain/weekly-plan.js';
import type { CommentId } from '../domain/comment.js';
import type {
  CheckInStore,
  Clock,
  CoachHired,
  CoachSpoke,
  CommentStore,
  MemberCalendar,
  PhotoFiles,
  ReactionStore,
  SportList,
  SquadMembership,
  WeeklyPlanStore,
} from '../ports.js';
import { deleteCheckIn, editCheckIn } from './check-ins/edit-check-in.js';
import { findPost } from './check-ins/find-post.js';
import { listMyCheckIns } from './check-ins/list-my-check-ins.js';
import { listMyPosts, type ListMyPostsInput, type MyPostsPage } from './check-ins/list-my-posts.js';
import {
  listSquadCheckIns,
  type ListSquadCheckInsInput,
  type SquadPost,
} from './check-ins/list-squad-check-ins.js';
import { memberWeek, planSharedTo, type MemberWeek } from './check-ins/member-week.js';
import { records, type Records } from './check-ins/records.js';
import { currentStreaks, type CurrentStreaks } from './check-ins/current-streaks.js';
import { squadToday, type SquadToday } from './check-ins/squad-today.js';
import {
  reactToCheckIn,
  type ReactToCheckInInput,
  type Reacted,
} from './check-ins/react-to-check-in.js';
import { removeResponse } from './check-ins/responses.js';
import { responsesReceived } from './check-ins/reactions-received.js';
import {
  commentOnCheckIn,
  deleteComment,
  type CommentInput,
  type Commented,
} from './check-ins/comments.js';
import { squadWeekSummary, type SquadWeekSummary } from './check-ins/week-summary.js';
import { placedPosts } from './check-ins/placed-posts.js';
import { squadTrainings, weekStartNow } from './check-ins/squad-goal-weeks.js';
import {
  squadWeekCheckIns,
  squadsCheckedInto,
  type SquadWeekCheckIns,
} from './check-ins/week-for-awards.js';
import {
  saveCheckIn,
  type SaveCheckInInput,
  type SavedCheckIn,
} from './check-ins/save-check-in.js';

/** Daily check-ins: saving them, reading them back, and teammates' reactions and comments. */
export interface CheckIns {
  save(input: SaveCheckInInput): Promise<SavedCheckIn>;
  /** Replaces the fields and photos of the member's own check-in; the same edit again is a no-op. */
  edit(input: {
    readonly id: CheckInId;
    readonly member: MemberId;
    readonly edit: CheckInEdit;
  }): Promise<CheckInRecord>;
  /** Deletes the member's own check-in with its photos and everything left on it. */
  delete(input: { readonly id: CheckInId; readonly member: MemberId }): Promise<void>;
  /** A check-in as it is saved now, whoever made it; undefined once it is deleted. */
  current(id: CheckInId): Promise<CheckInRecord | undefined>;
  /** A squad's feed: its check-ins for a range of days, each with its reactions and comments. */
  listForSquad(input: ListSquadCheckInsInput): Promise<SquadPost[]>;
  /**
   * The posts in a squad's 动态 tagged with a place, newest first, for a member of it: what its
   * places are worked out from.
   */
  placedPosts(input: {
    readonly squad: SquadId;
    readonly viewer: MemberId;
  }): Promise<CheckInRecord[]>;
  /** One post, as the feed shows it, for its author or a teammate who can see it. */
  post(input: { readonly id: CheckInId; readonly viewer: MemberId }): Promise<SquadPost>;
  listMine(input: {
    readonly member: MemberId;
    readonly days: DayRange;
    readonly unshared?: Unshared;
  }): Promise<CheckInRecord[]>;
  /** The member's history (历史动态): their own check-ins, newest first, a page at a time. */
  listMyPosts(input: ListMyPostsInput): Promise<MyPostsPage>;
  /** Everything the member ever checked in, counted by kind, wherever it went. */
  totals(member: MemberId): Promise<CheckInTotals>;
  /**
   * The same counts of only what `member` shared to `squad`, for what the squad's coach reads:
   * a post kept to the member never reaches it.
   */
  totalsSharedTo(query: {
    readonly member: MemberId;
    readonly squad: SquadId;
  }): Promise<CheckInTotals>;
  /** The member's 训练 check-ins made from `since` on, the earliest made first. */
  trainedSince(query: {
    readonly member: MemberId;
    readonly since: Date;
  }): Promise<TrainedCheckIn[]>;
  /** The member's 训练 for a range of days (训练记录 on 我), by day, the earliest made first. */
  trainings(query: {
    readonly member: MemberId;
    readonly from: string;
    readonly to: string;
  }): Promise<TrainingDay[]>;
  /** 外卡记录: the member's records since they joined, and how they stand in their squad. */
  records(member: MemberId): Promise<Records>;
  /** The member's streaks still going, for the player card; with `squad`, as squadmates see them. */
  currentStreaks(query: {
    readonly member: MemberId;
    readonly squad?: SquadId;
  }): Promise<CurrentStreaks>;
  react(input: ReactToCheckInInput): Promise<Reacted>;
  removeReaction(input: { readonly checkIn: CheckInId; readonly member: MemberId }): Promise<void>;
  /** Teammates who reacted to the member's check-ins in `[since, until)`, with any emoji. */
  reactionsReceived(input: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<ReadonlySet<MemberId>>;
  /** Teammates who commented on the member's check-ins in `[since, until)`. */
  commentsReceived(input: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<ReadonlySet<MemberId>>;
  comment(input: CommentInput): Promise<Commented>;
  deleteComment(input: {
    readonly checkIn: CheckInId;
    readonly id: CommentId;
    readonly member: MemberId;
  }): Promise<void>;
  /** The home screen's squad: each member's today and the week's counts, for one of them. */
  squadToday(input: { readonly viewer: MemberId; readonly squad: SquadId }): Promise<SquadToday>;
  /**
   * A member's own 本周 x/y, for a squadmate's view of their card: the week and today on
   * `squadZone`, the squad's clock, so every squadmate sees the same week.
   */
  memberWeek(input: {
    readonly member: MemberId;
    readonly viewer: MemberId;
    readonly squad: SquadId;
    readonly squadZone: string;
  }): Promise<MemberWeek>;
  /**
   * A member's plan for a week as the squad may see it: a day a 训练 the squad can't see turned
   * reads as the member planned it.
   */
  planSharedTo(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<PlanDays>;
  /** The Monday of the member's week now, in their time zone. */
  weekStartNow(member: MemberId): Promise<WeekStart>;
  /**
   * The 训练 these members sent to the squad in a week, several on one day each counting: what the
   * squad's weekly goal (小队每周目标, 人均 N 次) counts.
   */
  squadTrainings(input: {
    readonly squad: SquadId;
    readonly members: readonly MemberId[];
    readonly weekStart: WeekStart;
  }): Promise<number>;
  /** A squad's week (周日战报): its awards and counts, for one of its members. */
  weekSummary(input: {
    readonly viewer: MemberId;
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<SquadWeekSummary>;
  /** The squads that got a check-in for a day of the week made before `before`. */
  squadsCheckedInto(input: {
    readonly weekStart: WeekStart;
    readonly before: Date;
  }): Promise<SquadId[]>;
  /**
   * A squad's week as it stood at `before` for these members (who was in it then), for the
   * week's awards and its frozen 战报.
   */
  squadWeekCheckIns(input: {
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
    readonly before: Date;
    readonly members: readonly MemberId[];
  }): Promise<SquadWeekCheckIns>;
}

export function createCheckIns(deps: {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
  readonly reactions: ReactionStore;
  readonly comments: CommentStore;
  /** Whether a coach spoke under a check-in, so members may reply to it. */
  readonly coachSpoke?: CoachSpoke;
  /** Whether a squad has a coach hired now, so members may @ it. */
  readonly coachHired?: CoachHired;
  readonly photos: PhotoFiles;
  /** Which sports a 训练 may name. */
  readonly sports: SportList;
  readonly plans: WeeklyPlanStore;
  readonly calendarOf: MemberCalendar;
  readonly clock: Clock;
}): CheckIns {
  return {
    save: (input) => saveCheckIn(deps, input),
    edit: (input) => editCheckIn(deps, input),
    delete: (input) => deleteCheckIn(deps, input),
    current: (id) => deps.store.find(id),
    listForSquad: (input) => listSquadCheckIns(deps, input),
    post: (input) => findPost(deps, input),
    placedPosts: (input) => placedPosts(deps, input),
    listMine: (input) => listMyCheckIns(deps, input),
    listMyPosts: (input) => listMyPosts(deps, input),
    totals: (member) => deps.store.totals(member),
    totalsSharedTo: (query) => deps.store.totalsSharedTo(query),
    trainedSince: (query) => deps.store.trainedSince(query),
    trainings: (query) => deps.store.trainingsForMember(query),
    records: (member) => records(deps, member),
    currentStreaks: (query) => currentStreaks(deps, query),
    react: (input) => reactToCheckIn(deps, input),
    removeReaction: (input) =>
      removeResponse({ ...deps, remove: (...at) => deps.reactions.remove(...at) }, input),
    reactionsReceived: (input) =>
      responsesReceived(
        { ...deps, receivedBy: (query) => deps.reactions.receivedBy(query) },
        input,
      ),
    commentsReceived: (input) =>
      responsesReceived({ ...deps, receivedBy: (query) => deps.comments.receivedBy(query) }, input),
    comment: (input) => commentOnCheckIn(deps, input),
    deleteComment: (input) => deleteComment(deps, input),
    squadToday: (input) => squadToday(deps, input),
    memberWeek: (input) => memberWeek(deps, input),
    planSharedTo: (input) => planSharedTo(deps, input),
    weekStartNow: (member) => weekStartNow(deps, member),
    squadTrainings: (input) => squadTrainings(deps, input),
    weekSummary: (input) => squadWeekSummary(deps, input),
    squadsCheckedInto: (input) => squadsCheckedInto(deps, input),
    squadWeekCheckIns: (input) => squadWeekCheckIns(deps, input),
  };
}
