import { mentionsSelfHarm } from '@wildcard/typed-text';

import { promptKey, type MemberWeek, type WeekCheckIn } from './awards.js';
import { AWARD_MOVES } from './moves.js';
import type { WeekStart } from './schedule.js';

// The prompt for a squad's weekly awards. The product spec owns its wording and its eval cases
// (the awards prompt next to the 请假条 one): change it there first, then here. Members go by
// a letter, never their id or name, and only those who checked in are listed, so the model
// can't write about anyone who didn't.

export const INSTRUCTIONS = `你在给一个朋友运动打卡 App 的小队写「本周颁奖」：周日晚上，根据这一周每个人真实的打卡记录，给每个人颁 1 到 3 个好笑的头衔。

输入：这周每个队员的代号和记录（每天练了什么运动、健康餐/放纵餐、请假条和原因、配的一句话、打卡时间），以及可用的动作列表。
输出：每个有打卡的队员 1–3 个奖。

每个奖：
- 头衔：最多 6 个字，像外号或奖项名，一看就知道在夸什么。例：网球场钉子户、雨中狠人、请假条文豪、早八战神。
- 颁奖词：一句话，最多 24 个字，必须提到这周真实发生的一件事（哪天、什么运动、什么情况），像颁奖典礼主持人念的。
- 动作：从可用动作列表里挑一个最贴这个奖的，只能用列表里的 id。

怎么写：
- 只夸人，或者自嘲式的好笑。请假多的人也要拿到夸人的头衔（比如夸他请假条写得好）。
- 每个人的奖要不一样，同一个小队里不要重复的头衔。
- 只用输入里有的事，不要编。
- 英文词原样保留（oncall、PR 等）。运动的英文代号（tennis、run）写成中文。
- 不要在头衔和颁奖词里写队员代号。

不要写：
- 体重、身材、长相、热量、饮食控制。
- 拿人开涮、比较谁练得少、「垫底」「最懒」这类话。
- 自责、愧疚、「下周一定」这类压力话。
- 没有打卡的队员：不要给他们写任何东西。
- emoji、感叹号连用、「作为一个…」这类 AI 腔。

只输出 JSON：{"version":1,"awards":[{"member":"<代号>","titles":[{"title":"…","speech":"…","move":"<动作 id>"}]}]}`;

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
 * What the model is told of a member's own words (a sport they named included): never words
 * about self-harm, which no award may joke about or quote.
 */
const told = (text: string) => (mentionsSelfHarm(text) ? '（略）' : text);

/**
 * The user message: the week as JSON, members who checked in by letter in the order given,
 * each day's check-ins, and the moves to pick from.
 */
export function promptFor(week: {
  readonly weekStart: WeekStart;
  readonly members: readonly MemberWeek[];
}): string {
  return JSON.stringify({
    version: 1,
    week: week.weekStart,
    members: week.members.map(({ timeZone, checkIns }, index) => ({
      member: promptKey(index),
      checkIns: checkIns.map((each) => ({
        day: `${each.day} ${WEEKDAYS[new Date(Date.parse(each.day)).getUTCDay()] ?? ''}`,
        time: timeOfDay(each.createdAt, timeZone),
        kind: KIND_NAMES[each.kind],
        ...(each.sport === undefined ? {} : { sport: told(each.sport) }),
        ...(each.text === undefined ? {} : { reason: told(each.text) }),
        ...(each.caption === undefined ? {} : { caption: told(each.caption) }),
        ...(each.photos.length === 0 ? {} : { photos: each.photos.length }),
      })),
    })),
    moves: Object.entries(AWARD_MOVES).map(([id, description]) => ({ id, description })),
  });
}
