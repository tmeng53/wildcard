import type { CheckInId, CheckInRecord, MemberId, SquadId } from '../domain/check-in.js';
import type { DayRange } from '../domain/day-range.js';
import type { CheckInTotals } from '../domain/totals.js';
import type { WeekStart } from '../domain/weekly-plan.js';
import type { Reaction } from '../domain/reaction.js';
import type {
  CheckInStore,
  Clock,
  MemberCalendar,
  PhotoFiles,
  ReactionStore,
  SportList,
  SquadMembership,
  WeeklyPlanStore,
} from '../ports.js';
import { listMyCheckIns } from './check-ins/list-my-check-ins.js';
import {
  listSquadCheckIns,
  type ListSquadCheckInsInput,
  type SquadPost,
} from './check-ins/list-squad-check-ins.js';
import { squadToday, type SquadToday } from './check-ins/squad-today.js';
import {
  reactToCheckIn,
  type ReactToCheckInInput,
  type Reacted,
} from './check-ins/react-to-check-in.js';
import { listResponses, removeResponse } from './check-ins/responses.js';
import { reactionsReceived } from './check-ins/reactions-received.js';
import { squadWeekSummary, type SquadWeekSummary } from './check-ins/week-summary.js';
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

/** Daily check-ins: saving them, reading them back, and teammates' reactions. */
export interface CheckIns {
  save(input: SaveCheckInInput): Promise<SavedCheckIn>;
  /** A squad's feed: its check-ins for a range of days, each with its reactions. */
  listForSquad(input: ListSquadCheckInsInput): Promise<SquadPost[]>;
  listMine(input: { readonly member: MemberId; readonly days: DayRange }): Promise<CheckInRecord[]>;
  /** Everything the member ever checked in, counted by kind, wherever it went. */
  totals(member: MemberId): Promise<CheckInTotals>;
  react(input: ReactToCheckInInput): Promise<Reacted>;
  removeReaction(input: { readonly checkIn: CheckInId; readonly member: MemberId }): Promise<void>;
  listReactions(input: {
    readonly checkIn: CheckInId;
    readonly viewer: MemberId;
  }): Promise<Reaction[]>;
  /** Teammates who reacted to the member's check-ins in `[since, until)`, with any emoji. */
  reactionsReceived(input: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<ReadonlySet<MemberId>>;
  /** The home screen's squad: each member's today and the week's counts, for one of them. */
  squadToday(input: { readonly viewer: MemberId; readonly squad: SquadId }): Promise<SquadToday>;
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
  readonly photos: PhotoFiles;
  /** Which sports a 练了 may name. */
  readonly sports: SportList;
  readonly plans: WeeklyPlanStore;
  readonly calendarOf: MemberCalendar;
  readonly clock: Clock;
}): CheckIns {
  return {
    save: (input) => saveCheckIn(deps, input),
    listForSquad: (input) => listSquadCheckIns(deps, input),
    listMine: (input) => listMyCheckIns(deps, input),
    totals: (member) => deps.store.totals(member),
    react: (input) => reactToCheckIn(deps, input),
    removeReaction: (input) =>
      removeResponse({ ...deps, remove: (...at) => deps.reactions.remove(...at) }, input),
    listReactions: (input) =>
      listResponses({ ...deps, list: (checkIn) => deps.reactions.list(checkIn) }, input),
    reactionsReceived: (input) => reactionsReceived(deps, input),
    squadToday: (input) => squadToday(deps, input),
    weekSummary: (input) => squadWeekSummary(deps, input),
    squadsCheckedInto: (input) => squadsCheckedInto(deps, input),
    squadWeekCheckIns: (input) => squadWeekCheckIns(deps, input),
  };
}
