import {
  promptKey,
  topCheckInOf,
  type MemberId,
  type MemberWeek,
  type SquadPages,
  type WeekCheckIn,
} from './awards.js';
import { AwardMove } from './moves.js';
import type { AwardSettings } from './settings.js';
import type { WeekStart } from './schedule.js';

// The user message for a squad's weekly awards. The standing instructions and the moves'
// descriptions are settings, kept in the database (AwardSettings), so their wording changes
// without a deploy; the product spec owns it and its eval cases (the awards prompt next to the
// 请假条 one). Members go by a letter, never their id or name, and only those who checked in are
// listed, so the model can't write about anyone who didn't.

const KIND_NAMES: Record<WeekCheckIn['kind'], string> = {
  trained: '练了',
  healthyMeal: '健康餐',
  cheatMeal: '放纵餐',
  disclaimer: '请假条',
};

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/** `HH:MM` on the member's own clock. */
function timeOfDay(moment: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(moment);
}

/**
 * The user message: the week as JSON, members who checked in by letter in the order given,
 * each day's check-ins (their most-reacted one marked `hottest`), the facts of the squad's
 * pages, and the moves to pick from. A page's fact that names a member not listed (one who
 * didn't agree to AI use) is left out, with their words. The moves are described as the
 * settings have them.
 */
export function promptFor(week: {
  readonly weekStart: WeekStart;
  readonly members: readonly MemberWeek[];
  readonly pages: SquadPages;
  readonly moves: AwardSettings['moves'];
}): string {
  const keys = new Map(week.members.map(({ member }, index) => [member, promptKey(index)]));
  const keyOf = (member: MemberId) => keys.get(member);
  const { podium, meals, bestDisclaimer, ending } = week.pages;
  const champion = podium === undefined ? undefined : keyOf(podium.champion);
  const author = bestDisclaimer === undefined ? undefined : keyOf(bestDisclaimer.author);
  return JSON.stringify({
    version: 1,
    week: week.weekStart,
    members: week.members.map(({ timeZone, plannedDays, trainedDays, checkIns }, index) => {
      const hottest = topCheckInOf(checkIns)?.checkIn;
      return {
        member: promptKey(index),
        plannedDays,
        trainedDays,
        checkIns: checkIns.map((each) => ({
          day: `${each.day} ${WEEKDAYS[new Date(Date.parse(each.day)).getUTCDay()] ?? ''}`,
          time: timeOfDay(each.createdAt, timeZone),
          kind: KIND_NAMES[each.kind],
          ...(each.sport === undefined ? {} : { sport: each.sport }),
          ...(each.text === undefined ? {} : { reason: each.text }),
          ...(each.caption === undefined ? {} : { caption: each.caption }),
          ...(each.photos.length === 0 ? {} : { photos: each.photos.length }),
          ...(each.id === hottest ? { hottest: true } : {}),
        })),
      };
    }),
    pages: {
      ...(podium === undefined || champion === undefined
        ? {}
        : {
            podium: {
              champion,
              sides: podium.sides.flatMap((side) => keyOf(side) ?? []),
            },
          }),
      ...(meals === undefined ? {} : { meals }),
      ...(bestDisclaimer === undefined || author === undefined
        ? {}
        : { bestDisclaimer: { author, reason: bestDisclaimer.text } }),
      ...(ending === undefined ? {} : { ending: { ...ending, hit: ending.done >= ending.plan } }),
    },
    // In the moves' own order, whatever order the database keeps them in.
    moves: AwardMove.options.map((id) => ({ id, description: week.moves[id] })),
  });
}
