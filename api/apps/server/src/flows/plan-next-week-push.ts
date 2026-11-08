import type { Members } from '@wildcard/members';
import { MemberId as NoticeMember, type Notices } from '@wildcard/notices';
import {
  LocalDay,
  MemberId as PushMember,
  type PlanReminderCandidate,
  type Push,
  type PushNotification,
} from '@wildcard/push';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';
import { noticeAlert } from './daily-progress-push.js';

/** How many members' pushes are sent at once. */
const AT_ONCE = 8;

/** Sunday, as ISO numbers the days of the week. */
const SUNDAY = 7;

export interface PlanNextWeekDependencies {
  readonly members: Pick<Members, 'pastLocalHour'>;
  readonly push: Push;
  /** Where each push sent is kept for the member's 通知. */
  readonly notices: Notices;
  readonly clock: () => Date;
  readonly log: Log;
}

/** What a run did, member by member. */
export interface PlanNextWeekRun {
  /** Members whose push was due: their Sunday past the time, not turned off, not handled. */
  readonly due: number;
  /** Reached at least one of the member's phones. */
  readonly sent: number;
  /** Reached no phone: none, sending is off, or every phone failed. Kept in 通知 all the same. */
  readonly unsent: number;
  /** Another run handled them first. */
  readonly skipped: number;
}

/**
 * 去安排下周 (Tracy, 2026-11-08): once each member's Sunday clock passes the time the push
 * settings name (8:30pm to begin with), one push asking them to plan next week's 出赛表, to
 * everyone whether or not they already have; a tap opens 出赛表 on that week. It goes under the
 * member's daily push switch, and is kept in their 通知. Meant to run every few minutes with the
 * daily push; each member's week is claimed before sending, so runs can overlap or repeat.
 */
export async function sendPlanNextWeek(deps: PlanNextWeekDependencies): Promise<PlanNextWeekRun> {
  const settings = await deps.push.dailySettings();
  if (!settings.planReminderSending) return { due: 0, sent: 0, unsent: 0, skipped: 0 };
  const sunday = await deps.members.pastLocalHour({
    hour: settings.planReminderHour,
    minute: settings.planReminderMinute,
    isoWeekday: SUNDAY,
    now: deps.clock(),
  });
  const due = await deps.push.planReminderDue(
    sunday.map(({ member, day }) => ({
      member: PushMember.parse(member),
      week: LocalDay.parse(dayAfter(day)),
    })),
  );
  const outcomes: Outcome[] = [];
  for (let start = 0; start < due.length; start += AT_ONCE) {
    const batch = due.slice(start, start + AT_ONCE);
    outcomes.push(...(await Promise.all(batch.map((each) => handle(deps, each)))));
  }
  const count = (outcome: Outcome) => outcomes.filter((each) => each === outcome).length;
  return {
    due: due.length,
    sent: count('sent'),
    unsent: count('unsent'),
    skipped: count('skipped'),
  };
}

type Outcome = 'sent' | 'unsent' | 'skipped';

/** One member's push. Never throws, so one member's failure never stops the others'. */
async function handle(
  deps: PlanNextWeekDependencies,
  { member, week }: PlanReminderCandidate,
): Promise<Outcome> {
  try {
    if (!(await deps.push.claimPlanReminder({ member, week, at: deps.clock() }))) {
      return 'skipped';
    }
  } catch (error) {
    // Not claimed, so the next run tries again.
    deps.log.error('plan next week push not claimed', { member, week, error });
    return 'unsent';
  }
  const notification = planNextWeekNotification(week);
  try {
    await deps.notices.tell([
      {
        member: NoticeMember.parse(member),
        kind: 'planNextWeek',
        subject: { version: 1, alert: noticeAlert(notification), weekStart: week },
      },
    ]);
  } catch (error) {
    deps.log.warn('plan next week push not kept in notices', { member, error });
  }
  try {
    const outcome = await deps.push.notifyMembers({ members: [member], notification });
    if (outcome.failures.length > 0) {
      deps.log.warn('plan next week push not sent to every phone', {
        member,
        failures: outcome.failures,
      });
    }
    return outcome.sent > 0 ? 'sent' : 'unsent';
  } catch (error) {
    // Claimed already, so it isn't tried again: at most one a week.
    deps.log.error('plan next week push not sent', { member, week, error });
    return 'unsent';
  }
}

/**
 * The push, without its words: 去安排下周, and the week to open 出赛表 on (`week`, its Monday).
 * A later one replaces it on the phone rather than stacking, as each asks about its own week.
 */
export function planNextWeekNotification(week: string): PushNotification {
  return {
    alert: pushAlert('push.planNextWeek', []),
    category: 'planNextWeek',
    thread: 'planNextWeek',
    collapseId: `planNextWeek-${week}`,
    interruption: 'active',
    event: { kind: 'planNextWeek', week },
  };
}

/** The calendar day after `day` (`YYYY-MM-DD`). */
function dayAfter(day: string): string {
  const next = new Date(`${day}T00:00:00Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return next.toISOString().slice(0, 10);
}
