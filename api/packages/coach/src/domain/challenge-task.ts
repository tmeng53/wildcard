import { writeIn } from '@wildcard/language-model';

import { challengeHow, challengeText, type DayChallengeFacts } from './challenge.js';
import { planDayWords, planIndexOf, type NoteBrief } from './member-facts.js';
import { dayWords, postWhat, type WeekCheckIn } from './squad-week.js';

// The task of the run that sets each member's day challenge (Tracy, 2026-11-14: start from first
// principles). It reads only what a challenge is set from, member by member under their names:
// today's plan and the week's, what they posted (each post numbered, its comments looked up on
// demand), the recent challenges and how each went, and what the coach knows of them. Never the
// squad's talk, reactions or the coach's own rules.

/** One member the run sets a challenge for. */
export interface ChallengeMember {
  readonly member: string;
  /** What the morning's brief knows of them: plan, 饮食小目标, days trained, weather, language. */
  readonly brief: NoteBrief;
  /** Their page in the coach's memory, with names, when it has one. */
  readonly about?: string;
}

/**
 * The run's task, and the posts it numbered (动态N), which `post_comments` looks up. `posts` is
 * every post it may list, oldest first: this week's, and yesterday's when that was last week.
 */
export function challengeTaskOf({
  day,
  names,
  members,
  posts,
  challenges,
}: {
  readonly day: string;
  readonly names: ReadonlyMap<string, string>;
  readonly members: readonly ChallengeMember[];
  readonly posts: readonly WeekCheckIn[];
  readonly challenges: readonly DayChallengeFacts[];
}): { readonly task: string; readonly numbered: ReadonlyMap<string, WeekCheckIn> } {
  const numbered = new Map<string, WeekCheckIn>();
  const blocks = members.map(({ member, brief, about }) => {
    const lines = [`## ${names.get(member) ?? '队员'}`];
    const plan = brief.plan?.week;
    const today = plan?.[planIndexOf(day)];
    lines.push(`- 今天的计划：${today === undefined ? '没填出赛表' : planDayWords(today)}`);
    if (plan !== undefined && plan.length > 0) {
      lines.push(
        `- 这周出赛表：${plan.map((each, index) => `${WEEKDAYS[index] ?? ''}${planDayWords(each)}`).join('，')}`,
      );
    }
    if (brief.plan !== undefined && brief.plan.fuelGoals.length > 0) {
      lines.push(`- 这周饮食小目标：${brief.plan.fuelGoals.join('、')}`);
    }
    lines.push(`- 这周练了：${String(brief.trainedDays)} 天`);
    const mine = posts.filter((each) => each.member === member);
    if (mine.length === 0) {
      lines.push('- 最近发的：没有');
    } else {
      lines.push('- 最近发的：');
      for (const post of mine) {
        const number = `动态${String(numbered.size + 1)}`;
        numbered.set(number, post);
        lines.push(`  - ${number} · ${postLine(post)}`);
      }
    }
    const theirs = challenges.filter((each) => each.member === member);
    if (theirs.length > 0) {
      lines.push(
        '- 最近的挑战：',
        ...theirs.map(
          (each) =>
            `  - ${dayWords(each.day)}「${challengeText(each.challenge)}」：${challengeHow(each)}`,
        ),
      );
    }
    if (brief.weather !== undefined) {
      lines.push(
        `- 当地天气：${brief.weather.city === undefined ? '' : `${brief.weather.city}，`}${brief.weather.words}`,
      );
    }
    const known = about?.trim();
    if (known !== undefined && known !== '') lines.push(`- 你对他的了解：\n${known}`);
    lines.push(`- ${writeIn(brief.language ?? 'zh-Hans')}`);
    return lines.join('\n');
  });
  return {
    task: [`今天是 ${day}，${WEEKDAYS[planIndexOf(day)] ?? ''}。`, ...blocks].join('\n\n'),
    numbered,
  };
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/** One post in a line: `11-13 周五 篮球 15 分钟：「打篮球也是练了」（6 条评论）`. */
function postLine(post: WeekCheckIn): string {
  const words = [`${dayWords(post.day)} ${postWhat(post)}`];
  if (post.unposted === true) return `${words[0] ?? ''}（只记录，没发动态）`;
  if (post.text !== undefined) words.push(`：「${post.text}」`);
  if (post.comments.length > 0) words.push(`（${String(post.comments.length)} 条评论）`);
  return words.join('');
}
