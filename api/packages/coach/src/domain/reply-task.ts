import { writeIn, type ReaderLanguage } from '@wildcard/language-model';

import { challengeText, type Challenge, type ChallengeCompletion } from './challenge.js';
import type { Coach } from './coach.js';
import { planIndexOf, type NoteBrief, type PlanDayFacts } from './member-facts.js';
import { dayWords, postWhat, type SquadWeek, type WeekCheckIn } from './squad-week.js';

// The reply step (Tracy, 2026-11-14: one prompt for answering a post and answering a comment,
// written from first principles): the coach's soul and what a good reply is, then a task with
// only what this reply needs. Posts go by a number (动态N) the tools take, so the coach looks up
// what it wants instead of being handed the day's whole talk.

/** The standing instructions of a reply: the coach's soul, then the reply rules. */
export function replyInstructionsOf(
  settings: { readonly replyRules: string },
  coach: Pick<Coach, 'soul'>,
): string {
  return [coach.soul, settings.replyRules].join('\n\n');
}

/**
 * Each post's number for a run (动态N), the same in the task and in every tool that names one:
 * this week's posts numbered oldest first, and any older one a tool lists after them.
 */
export class PostNumbers {
  readonly #byNumber = new Map<string, WeekCheckIn>();
  readonly #byId = new Map<string, string>();

  constructor(posts: readonly WeekCheckIn[] = []) {
    for (const post of posts.toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime())) {
      this.of(post);
    }
  }

  /** The post's number, given it now if it has none. */
  of(post: WeekCheckIn): string {
    const known = this.#byId.get(post.id);
    if (known !== undefined) return known;
    const number = `动态${String(this.#byNumber.size + 1)}`;
    this.#byNumber.set(number, post);
    this.#byId.set(post.id, number);
    return number;
  }

  /** The post with this number, or `undefined`. */
  find(number: string): WeekCheckIn | undefined {
    return this.#byNumber.get(number.trim());
  }

  get size(): number {
    return this.#byNumber.size;
  }

  numbers(): string[] {
    return [...this.#byNumber.keys()];
  }
}

/** What a reply's task is made of. */
export interface ReplyFacts {
  readonly kind: 'checkIn' | 'comment';
  readonly week: SquadWeek;
  readonly roster: ReadonlyMap<string, string>;
  readonly numbers: PostNumbers;
  /** The post the reply goes under. */
  readonly post: WeekCheckIn;
  /** The member it answers: the post's author, or whoever wrote to the coach. */
  readonly to: string;
  /** The time now on the squad's clock, `11-12 周四 23:40`. */
  readonly now: string;
  /** The moment the wake answers: the post, or the line written to the coach. */
  readonly at: Date;
  /**
   * On a comment's wake, everything said under the post up to the line it answers, one a line
   * (`saidLines`), and whether that line @s the coach rather than replying to it.
   */
  readonly thread?: { readonly lines: readonly string[]; readonly mention: boolean };
  /** The member it answers, as the morning brief knows them. */
  readonly brief?: NoteBrief;
  /** Today, `YYYY-MM-DD`, on the member's own day. */
  readonly day: string;
  /** Today's challenge, only once the member took it up. */
  readonly challenge?: { readonly challenge: Challenge; readonly completion?: ChallengeCompletion };
  /** Posts other than this one under which the member and the coach talked over the last day. */
  readonly talkedUnder: readonly WeekCheckIn[];
  /** On a 请假条, the streaks it keeps going. */
  readonly keptStreaks?: { readonly training?: number; readonly meals?: number };
  /** What the coach knows of the member it answers: their page, whole. */
  readonly page?: { readonly path: string; readonly body: string | undefined };
  /** What is special about today, one line each (a holiday, a change of coach). */
  readonly today: readonly string[];
  /** The emoji the coach reacted with lately, newest first. */
  readonly recentEmoji: readonly string[];
  readonly language: ReaderLanguage;
}

/** The task of one reply: the post, the person, and the little else a reply needs. */
export function replyTaskOf(facts: ReplyFacts): string {
  const { kind, roster, numbers, post, to } = facts;
  const name = (member: string): string => roster.get(member) ?? '队员';
  const number = numbers.of(post);
  const heading =
    kind === 'checkIn'
      ? `# ${name(to)}发了${number}`
      : facts.thread?.mention === true
        ? `# ${name(to)}在${number}下面 @ 你`
        : `# ${name(to)}在${number}下面回复你`;
  return [
    `${heading}\n现在是 ${facts.now}（小队时间）。`,
    postBlock(post, { number, name }),
    ...(facts.thread === undefined
      ? []
      : [['## 评论区（先后顺序）', ...facts.thread.lines].join('\n')]),
    personBlock(facts, name),
    ...(facts.today.length === 0
      ? []
      : [['## 今天', ...facts.today.map((line) => `- ${line}`)].join('\n')]),
    `## 小队的人\n${[...roster.values()].join('、')}。小队的事、你和大家之间的事在 squad.md、memory.md，用 recall 查。`,
    ...(kind === 'checkIn'
      ? [
          `## 你最近点过的表情\n${facts.recentEmoji.length === 0 ? '还没点过。' : facts.recentEmoji.join(' ')}`,
        ]
      : []),
    `## 他 App 的语言\n${writeIn(facts.language)}`,
  ].join('\n\n');
}

function postBlock(
  post: WeekCheckIn,
  { number, name }: { readonly number: string; readonly name: (member: string) => string },
): string {
  const lines = [`## ${number} · ${name(post.member)} · ${kindWords(post)}`];
  if (post.postedDay !== undefined && post.postedDay !== post.day) {
    lines.push(`- 补打卡：算 ${dayWords(post.day)} 的，${dayWords(post.postedDay)} 才发`);
  } else if (post.postedTime !== undefined) {
    lines.push(`- ${dayWords(post.day)} ${post.postedTime} 发（${name(post.member)}当地时间）`);
  }
  if (post.place !== undefined) lines.push(`- 地点：${post.place}`);
  if (post.text !== undefined) lines.push(`- 写的：「${post.text}」`);
  const photos = post.photos?.length ?? 0;
  if (photos > 0) lines.push(`- 照片 ${String(photos)} 张，你还没看过（look_at_photos）`);
  return lines.join('\n');
}

/** A post's kind in words: `训练：匹克球 300 分钟`, `坦白放纵餐`. */
function kindWords(post: WeekCheckIn): string {
  return post.kind === 'trained' && post.restDay !== true
    ? `训练：${postWhat(post)}`
    : postWhat(post);
}

const WEEKDAYS = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

function planDayWords(day: PlanDayFacts | undefined): string {
  if (day === undefined) return '没填';
  return day.kind === 'rest' ? '休息' : (day.sport ?? '练（没定项目）');
}

/** The member the reply answers: their day, their week, and what the coach knows of them. */
function personBlock(facts: ReplyFacts, name: (member: string) => string): string {
  const { brief, numbers, post, to } = facts;
  const lines = [`## ${name(to)}`];
  if (brief?.plan !== undefined) {
    lines.push(`- 今天的计划：${planDayWords(brief.plan.week[planIndexOf(facts.day)])}`);
  }
  if (brief !== undefined) lines.push(`- 这周练了：${String(brief.trainedDays)} 天`);
  const theirs = facts.week.checkIns.filter(
    (each) => each.member === to && each.id !== post.id && each.createdAt <= facts.at,
  );
  if (theirs.length > 0) {
    lines.push(
      `- 这周发的：${theirs
        .map(
          (each) =>
            `${numbers.of(each)} ${WEEKDAYS[planIndexOf(each.day)] ?? ''}${kindWords(each)}`,
        )
        .join('；')}`,
    );
  }
  if (facts.challenge !== undefined) {
    lines.push(
      `- 今天的挑战：「${challengeText(facts.challenge.challenge)}」，${facts.challenge.completion === undefined ? '接了，还没完成' : '已经完成了'}`,
    );
  }
  const streaks = [
    ...(facts.keptStreaks?.training !== undefined && facts.keptStreaks.training >= 2
      ? [`训练 ${String(facts.keptStreaks.training)} 天`]
      : []),
    ...(facts.keptStreaks?.meals !== undefined && facts.keptStreaks.meals >= 2
      ? [`健康餐 ${String(facts.keptStreaks.meals)} 天`]
      : []),
  ];
  if (streaks.length > 0) {
    lines.push(`- 连续：${streaks.join('、')}（请假、休息、放纵餐那天不断，也不算一天）`);
  }
  if (facts.talkedUnder.length > 0) {
    lines.push(
      `- 过去一天你们还在 ${facts.talkedUnder.map((each) => numbers.of(each)).join('、')} 下面聊过（post_comments 可看）`,
    );
  }
  const body = facts.page?.body?.trim() ?? '';
  lines.push(
    body === ''
      ? `- 你对${name(to)}的了解：还没记过。`
      : `- 你对${name(to)}的了解（${facts.page?.path ?? ''}）：\n\`\`\`\n${body}\n\`\`\``,
  );
  return lines.join('\n');
}
