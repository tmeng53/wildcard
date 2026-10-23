import {
  promptKey,
  topCheckInOf,
  type MemberId,
  type MemberWeek,
  type SquadPages,
  type WeekCheckIn,
} from './awards.js';
import { AWARD_MOVES } from './moves.js';
import type { WeekStart } from './schedule.js';

// The prompt for a squad's weekly awards. The product spec owns its wording and its eval cases
// (the awards prompt next to the 请假条 one): change it there first, then here. Members go by
// a letter, never their id or name, and only those who checked in are listed, so the model
// can't write about anyone who didn't.

export const INSTRUCTIONS = `你在给一个朋友运动打卡 App 的小队写周日「本周战报」：一个像 Instagram story 的几页小视频，有颁奖、每个人的一周、吃了什么、最佳请假条，最后一页是全队这一周的结局。所有文字都根据这一周每个人真实的打卡记录来写。

输入：这周每个队员的代号和记录（每天练了什么运动、健康餐/放纵餐、请假条和原因、配的一句话、打卡时间，计划练几天、实际练了几天，最火的一条标了 hottest），pages 里是每一页的事实（领奖台、吃了、最佳请假条、全队这一周），以及可用的动作列表。

你要写：
1. order：中间四页 myWeek、hottest、meals、bestDisclaimer 的顺序，最有故事的放前面。
2. awards：每个有打卡的队员一项，每项 1 到 3 个奖。每个奖：
   - title：最多 6 个字，像外号或奖项名，一看就知道在夸什么。例：网球场钉子户、雨中狠人、请假条文豪、早八战神。
   - speech：颁奖词，一句话，最多 24 个字，必须提到这周真实发生的一件事（哪天、什么运动、什么情况），像颁奖典礼主持人念的。
   - move：从动作列表里挑一个最贴这个奖的，只能用列表里的 id。
   每项还有：
   - line：最多 12 个字，说 TA 这一周。
   - hottest：TA 有标了 hottest 的那条才写，否则 null。line 最多 18 个字，回应那条打卡；move 从动作列表里挑。
3. podium：pages 里有 podium 才写，否则 null。speech 是给冠军（champion）的颁奖词，最多 24 个字；championMove 和 sideMove 各从动作列表里挑一个。
4. meals：pages 里有 meals 才写，否则 null。line 最多 14 个字，说全队这周吃了什么，不评价吃得好坏、吃了多少。
5. bestDisclaimer：pages 里有 bestDisclaimer 才写，否则 null。authorMove 从动作列表里挑一个把这张请假条演出来；squadMove 只能是 laugh、pump、wave 之一，是队友看到的反应。
6. ending：pages 里有 ending 才写，否则 null。headline 最多 4 个字（如 稳了、差一点）；line 最多 18 个字，好笑；move：达标（hit 为 true）只能是 pump、wave，没达标只能是 warmup、stretch、pump。

怎么写：
- 只夸人，或者自嘲式的好笑。请假多的人也要拿到夸人的头衔（比如夸他请假条写得好）。
- 每个人的奖要不一样，同一个小队里不要重复的头衔。
- 只用输入里有的事，不要编。
- 英文词原样保留（oncall、PR 等）。运动的英文代号（tennis、run）写成中文。
- 不要在任何文字里写队员代号，也不要编名字；要指人时直接省略，或者用「TA」。
- 没达标的结局也不能有愧疚和压力，比如「还差 3 天。下周的腿已经在热身了」。

不要写：
- 体重、身材、长相、热量、饮食控制、吃得好坏。
- 拿人开涮、比较谁练得少、「垫底」「最懒」这类话。
- 自责、愧疚、「下周一定」「坚持」「连续几天」这类压力话。
- 如果某条文字提到自伤、不想活了或者很严重的痛苦，不要拿它写任何东西。
- 没有打卡的队员：不要给他们写任何东西。
- 奥运、五环、Olympic。
- emoji、感叹号连用、「作为一个…」这类 AI 腔。

只输出 JSON，字段和结构按给定的 schema，version 是 1。`;

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
 * didn't agree to AI use) is left out, with their words.
 */
export function promptFor(week: {
  readonly weekStart: WeekStart;
  readonly members: readonly MemberWeek[];
  readonly pages: SquadPages;
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
    moves: Object.entries(AWARD_MOVES).map(([id, description]) => ({ id, description })),
  });
}
