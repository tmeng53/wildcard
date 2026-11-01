import { promptKey, type MemberId, type MemberWeek, type WeekCheckIn } from './awards.js';
import { AwardMove } from './moves.js';
import type { AwardSettings } from './settings.js';
import type { WeekStart } from './schedule.js';

// The user message for a squad's weekly awards. The standing instructions and the moves'
// descriptions are settings, kept in the database (AwardSettings), so their wording changes
// without a deploy; the product spec owns it and its eval cases (the awards prompt next to the
// 请假条 one). Members go by a letter, never their id or name, and only those who checked in are
// listed, so the model can't write about anyone who didn't. Comments come with each check-in
// (its latest `PROMPT_COMMENTS`), their writers by letter too, or as 队友 when they aren't listed.
// The memes in use from the meme library come along, for the model to use where one fits.

const KIND_NAMES: Record<WeekCheckIn['kind'], string> = {
  trained: '练了',
  healthyMeal: '健康餐',
  cheatMeal: '放纵餐',
  disclaimer: '请假条',
};

/** How a comment's writer, or whom it replies to, goes when they aren't listed. */
const TEAMMATE = '队友';

/**
 * The most comments a check-in brings to the prompt, its latest ones: a bound on the model
 * call's size whatever a squad writes, well past what a squad of friends leaves on one post.
 */
export const PROMPT_COMMENTS = 20;

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

/** A meme from the meme library, as the prompt has it. */
export interface PromptMeme {
  readonly phrase: string;
  readonly meaning: string;
  readonly background: string;
}

/**
 * The user message: the week as JSON, members who checked in by letter in the order given,
 * each day's check-ins, the moves to pick from, described as the settings have them, and the
 * memes in use (left out when there are none).
 */
export function promptFor(week: {
  readonly weekStart: WeekStart;
  readonly members: readonly MemberWeek[];
  readonly moves: AwardSettings['moves'];
  readonly memes: readonly PromptMeme[];
}): string {
  const keys = new Map(week.members.map(({ member }, index) => [member, promptKey(index)]));
  const keyOf = (member: MemberId) => keys.get(member) ?? TEAMMATE;
  return JSON.stringify({
    version: 1,
    week: week.weekStart,
    members: week.members.map(({ timeZone, checkIns }, index) => ({
      member: promptKey(index),
      checkIns: checkIns.map((each) => ({
        day: `${each.day} ${WEEKDAYS[new Date(Date.parse(each.day)).getUTCDay()] ?? ''}`,
        time: timeOfDay(each.createdAt, timeZone),
        kind: KIND_NAMES[each.kind],
        ...(each.sport === undefined ? {} : { sport: each.sport }),
        ...(each.text === undefined ? {} : { reason: each.text }),
        ...(each.caption === undefined ? {} : { caption: each.caption }),
        ...(each.photos.length === 0 ? {} : { photos: each.photos.length }),
        ...(each.comments === undefined || each.comments.length === 0
          ? {}
          : {
              comments: each.comments.slice(-PROMPT_COMMENTS).map(({ member, text, replyTo }) => ({
                from: keyOf(member),
                ...(replyTo === undefined ? {} : { to: keyOf(replyTo) }),
                text,
              })),
            }),
      })),
    })),
    // In the moves' own order, whatever order the database keeps them in.
    moves: AwardMove.options.map((id) => ({ id, description: week.moves[id] })),
    ...(week.memes.length === 0
      ? {}
      : {
          memes: week.memes.map(({ phrase, meaning, background }) => ({
            phrase,
            meaning,
            background,
          })),
        }),
  });
}
