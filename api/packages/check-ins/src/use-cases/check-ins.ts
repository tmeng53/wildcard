import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../domain/check-in.js';
import type { DayRange } from '../domain/day-range.js';
import type { WeekStart } from '../domain/weekly-plan.js';
import type { Reaction } from '../domain/reaction.js';
import type { Reply } from '../domain/reply.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  PhotoFiles,
  ReactionStore,
  ReplyStore,
  SquadMembership,
  WeeklyPlanStore,
} from '../ports.js';
import { listMyCheckIns } from './check-ins/list-my-check-ins.js';
import {
  listSquadCheckIns,
  type ListSquadCheckInsInput,
} from './check-ins/list-squad-check-ins.js';
import { squadToday, type SquadToday } from './check-ins/squad-today.js';
import {
  reactToCheckIn,
  type ReactToCheckInInput,
  type Reacted,
} from './check-ins/react-to-check-in.js';
import {
  replyToDisclaimer,
  type Replied,
  type ReplyToDisclaimerInput,
} from './check-ins/reply-to-disclaimer.js';
import { listResponses, removeResponse } from './check-ins/responses.js';
import { squadWeekSummary, type SquadWeekSummary } from './check-ins/week-summary.js';
import {
  saveCheckIn,
  type SaveCheckInInput,
  type SavedCheckIn,
} from './check-ins/save-check-in.js';

/** Daily check-ins: saving them, reading them back, and teammates' reactions and replies. */
export interface CheckIns {
  save(input: SaveCheckInInput): Promise<SavedCheckIn>;
  listForSquad(input: ListSquadCheckInsInput): Promise<CheckInRecord[]>;
  listMine(input: { readonly member: MemberId; readonly days: DayRange }): Promise<CheckInRecord[]>;
  react(input: ReactToCheckInInput): Promise<Reacted>;
  removeReaction(input: { readonly checkIn: CheckInId; readonly member: MemberId }): Promise<void>;
  listReactions(input: {
    readonly checkIn: CheckInId;
    readonly viewer: MemberId;
  }): Promise<Reaction[]>;
  /** Replies are for 请假条 only, apart from reactions: a teammate may leave both. */
  reply(input: ReplyToDisclaimerInput): Promise<Replied>;
  removeReply(input: { readonly checkIn: CheckInId; readonly member: MemberId }): Promise<void>;
  listReplies(input: { readonly checkIn: CheckInId; readonly viewer: MemberId }): Promise<Reply[]>;
  /** The home screen's squad: each member's today and the week's counts, for one of them. */
  squadToday(input: { readonly viewer: MemberId; readonly squad: SquadId }): Promise<SquadToday>;
  /** A squad's week (周日战报): its awards and counts, for one of its members. */
  weekSummary(input: {
    readonly viewer: MemberId;
    readonly squad: SquadId;
    readonly weekStart: WeekStart;
  }): Promise<SquadWeekSummary>;
}

export function createCheckIns(deps: {
  readonly store: CheckInStore;
  readonly membership: SquadMembership;
  readonly reactions: ReactionStore;
  readonly replies: ReplyStore;
  readonly photos: PhotoFiles;
  readonly plans: WeeklyPlanStore;
  readonly calendarOf: MemberCalendar;
  readonly clock: Clock;
}): CheckIns {
  return {
    save: (input) => saveCheckIn(deps, input),
    listForSquad: (input) => listSquadCheckIns(deps, input),
    listMine: (input) => listMyCheckIns(deps, input),
    react: (input) => reactToCheckIn(deps, input),
    removeReaction: (input) =>
      removeResponse({ ...deps, remove: (...at) => deps.reactions.remove(...at) }, input),
    listReactions: (input) =>
      listResponses({ ...deps, list: (checkIn) => deps.reactions.list(checkIn) }, input),
    reply: (input) => replyToDisclaimer(deps, input),
    removeReply: (input) =>
      removeResponse({ ...deps, remove: (...at) => deps.replies.remove(...at) }, input),
    listReplies: (input) =>
      listResponses({ ...deps, list: (checkIn) => deps.replies.list(checkIn) }, input),
    squadToday: (input) => squadToday(deps, input),
    weekSummary: (input) => squadWeekSummary(deps, input),
  };
}
