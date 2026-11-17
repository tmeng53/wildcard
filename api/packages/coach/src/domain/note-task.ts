import { writeIn, type ReaderLanguage } from '@wildcard/language-model';

import { challengeText, type Challenge } from './challenge.js';
import {
  memberBlocks,
  postNumberer,
  todayHeading,
  type ChallengeMember,
} from './challenge-task.js';
import type { Coach } from './coach.js';
import { giftBlock, type DayTalk, type GiftOptions } from './prompt.js';
import { dayWords, postWhat, type WeekCheckIn } from './squad-week.js';
import { peopleOf, personOf, type Roster } from './roster.js';

// The morning's notes (Tracy, 2026-11-14: each step from first principles): the coach's soul and
// what a good 战术板 line and 便条 are, then a task of only what the morning needs. Each member
// as the challenge run reads them, with the challenge it set; the squad's talk and reactions are
// looked up by post number, never dumped.

/** The standing instructions of the morning's notes: the coach's soul, then the note rules. */
export function noteInstructionsOf(
  settings: { readonly noteRules: string },
  coach: Pick<Coach, 'soul'>,
): string {
  return [coach.soul, settings.noteRules].join('\n\n');
}

/** What the morning's task is made of. */
export interface NoteFacts {
  readonly day: string;
  readonly names: Roster;
  /** Whom a note goes to, in order, with what the morning knows of each. */
  readonly members: readonly ChallengeMember[];
  /** The posts a member's block may list, oldest first. */
  readonly posts: readonly WeekCheckIn[];
  /** Today's challenge each member was set, by member id. */
  readonly set: ReadonlyMap<string, Challenge>;
  /** The talk under posts over the last day, where the coach was in it. */
  readonly talks: readonly DayTalk[];
  /** The squad's last 战术板 lines, newest first. */
  readonly recentNotes: readonly { readonly day: string; readonly text: string }[];
  /** The squad's language, which the 战术板 is written in. */
  readonly language: ReaderLanguage;
  /** What is special about today, one line each (a holiday, a change of coach). */
  readonly today: readonly string[];
  readonly gifting?: GiftOptions;
}

/** The morning's task, and the posts it numbered (动态N), which the tools go on from. */
export function noteTaskOf(facts: NoteFacts): {
  readonly task: string;
  readonly numbered: ReadonlyMap<string, WeekCheckIn>;
} {
  const { day, names, members, set, talks } = facts;
  // How past challenges went is the challenge run's to weigh; a note told it nags about them.
  const { blocks, numbered: listed } = memberBlocks({
    ...facts,
    challenges: [],
    more: (member, numberOf) => {
      const lines: string[] = [];
      const challenge = set.get(member);
      lines.push(
        challenge === undefined
          ? '- 今天的挑战：没有'
          : `- 今天的挑战：「${challengeText(challenge)}」${challenge.line === undefined ? '' : `，小字：${challenge.line}`}`,
      );
      const talked = talks.filter(
        ({ checkIn, said }) =>
          checkIn.member === member || said.some((each) => each.member === member),
      );
      if (talked.length > 0) {
        lines.push(
          `- 过去一天你们在 ${talked.map(({ checkIn }) => numberOf(checkIn)).join('、')} 下面聊过（post_comments 可看）`,
        );
      }
      return lines;
    },
  });
  const numbered = new Map(listed);
  const board = [
    '## 战术板',
    `- ${writeIn(facts.language)}`,
    ...squadLines({ day, names, posts: facts.posts, numbered }),
    ...(facts.recentNotes.length === 0
      ? ['- 你还没写过。']
      : ['- 你最近写过：', ...facts.recentNotes.map(({ day: at, text }) => `  - ${at}：${text}`)]),
    '- 小队的事、你和大家之间的事在 squad.md、memory.md，用 recall 查。',
  ].join('\n');
  return {
    task: [
      `# 早上\n${todayHeading(day)}`,
      ...(facts.today.length === 0
        ? []
        : [['## 今天', ...facts.today.map((line) => `- ${line}`)].join('\n')]),
      board,
      members.length === 0
        ? '## 便条\n今天没有要写便条的人。'
        : `## 便条（下面每人一张）\n小队的人（括号里是 user_id）：${peopleOf(names)}。`,
      ...blocks,
      ...giftBlock(facts.gifting, names),
    ].join('\n\n'),
    numbered,
  };
}

/**
 * What the whole squad did, for the 战术板 (2026-11-16: given only each member's plan, the coach
 * summed the plans up every morning): yesterday's posts by everyone, by number, and this week's
 * 训练 so far. Posts no member block listed get the next numbers, in the same map.
 */
function squadLines({
  day,
  names,
  posts,
  numbered,
}: {
  readonly day: string;
  readonly names: Roster;
  readonly posts: readonly WeekCheckIn[];
  readonly numbered: Map<string, WeekCheckIn>;
}): readonly string[] {
  const numberOf = postNumberer(numbered);
  const yesterday = new Date(Date.parse(`${day}T00:00:00Z`) - 86_400_000)
    .toISOString()
    .slice(0, 10);
  // A post kept off the 动态 still counts in the week, but is never listed.
  const ofYesterday = posts.filter((post) => post.day === yesterday && post.unposted !== true);
  const monday = mondayOf(day);
  const trained = posts.filter(
    (post) =>
      post.kind === 'trained' && post.restDay !== true && post.day >= monday && post.day < day,
  );
  const who = new Set(trained.map(({ member }) => member));
  return [
    ofYesterday.length === 0
      ? `- 昨天（${dayWords(yesterday)}）全队没人发动态。`
      : `- 昨天（${dayWords(yesterday)}）全队发的：${ofYesterday
          .map((post) => `${personOf(names, post.member)} ${postWhat(post)}（${numberOf(post)}）`)
          .join('，')}`,
    day === monday
      ? '- 今天是新一周的第一天。'
      : `- 这周到昨天，全队练了 ${String(trained.length)} 次，${String(who.size)} 个人练过。`,
  ];
}

/** The Monday of `day`'s week, `YYYY-MM-DD`. */
function mondayOf(day: string): string {
  const at = Date.parse(`${day}T00:00:00Z`);
  const back = (new Date(at).getUTCDay() + 6) % 7;
  return new Date(at - back * 86_400_000).toISOString().slice(0, 10);
}
