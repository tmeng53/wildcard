import { describe, expect, it } from 'vitest';

import { PostNumbers, replyInstructionsOf, replyTaskOf, type ReplyFacts } from './reply-task.js';
import { rosterOf, type SquadWeek, type WeekCheckIn } from './squad-week.js';

const mia = '11111111-1111-4111-8111-111111111111';
const leo = '22222222-2222-4222-8222-222222222222';

const run: WeekCheckIn = {
  id: 'c1',
  member: mia,
  day: '2026-10-27',
  createdAt: new Date('2026-10-27T12:00:00Z'),
  postedTime: '08:00',
  kind: 'trained',
  sport: '跑步',
  minutes: 30,
  text: '腿废了',
  reactedBy: [leo],
  comments: [{ id: 'k1', member: leo, text: '强', at: new Date('2026-10-27T12:30:00Z') }],
};
const meal: WeekCheckIn = {
  id: 'c2',
  member: mia,
  day: '2026-10-28',
  createdAt: new Date('2026-10-28T12:00:00Z'),
  postedTime: '08:00',
  kind: 'cheatMeal',
  text: '炸鸡',
  photos: ['m/a.jpg', 'm/b.jpg'],
  reactedBy: [],
  comments: [],
};
const week: SquadWeek = {
  weekStart: '2026-10-26',
  members: [
    { member: mia, nickname: '米亚' },
    { member: leo, nickname: '里奥' },
  ],
  checkIns: [meal, run],
};

function facts(more: Partial<ReplyFacts> = {}): ReplyFacts {
  return {
    kind: 'checkIn',
    week,
    roster: rosterOf(week),
    numbers: new PostNumbers(week.checkIns),
    post: meal,
    to: mia,
    now: '10-28 周三 08:05',
    at: meal.createdAt,
    day: '2026-10-28',
    talkedUnder: [],
    today: [],
    recentEmoji: [],
    language: 'zh-Hans',
    ...more,
  };
}

describe('the reply step', () => {
  it('reads the coach’s soul, then the reply rules, and nothing shared with other steps', () => {
    expect(replyInstructionsOf({ replyRules: '接住他最在意的事。' }, { soul: '你是暖暖。' })).toBe(
      '你是暖暖。\n\n接住他最在意的事。',
    );
  });

  it('numbers the week’s posts oldest first, the same in the task and the tools', () => {
    const numbers = new PostNumbers(week.checkIns);
    expect(numbers.of(run)).toBe('动态1');
    expect(numbers.of(meal)).toBe('动态2');
    expect(numbers.find(' 动态2 ')).toBe(meal);
    expect(numbers.find('动态3')).toBeUndefined();
    // A post a tool lists from an older week gets the next number, and keeps it.
    const older = { ...run, id: 'c0' };
    expect(numbers.of(older)).toBe('动态3');
    expect(numbers.of(older)).toBe('动态3');
  });

  it('tells a post’s reply the post, its author’s day and week, and what it knows of them', () => {
    const task = replyTaskOf(
      facts({
        brief: {
          name: '米亚',
          trainedDays: 1,
          plan: {
            week: [
              { kind: 'train', sport: '跑步' },
              { kind: 'rest' },
              { kind: 'train', sport: '力量' },
              { kind: 'rest' },
              { kind: 'rest' },
              { kind: 'rest' },
              { kind: 'rest' },
            ],
            fuelGoals: [],
          },
        },
        challenge: { challenge: { title: '做深蹲', amount: 30, unit: '个' } },
        talkedUnder: [run],
        page: { path: 'people/米亚.md', body: '- 米亚爱吃炸鸡' },
        recentEmoji: ['🔥', '💪'],
      }),
    );
    expect(task).toBe(
      [
        '# 米亚发了动态2\n现在是 10-28 周三 08:05（小队时间）。',
        '## 动态2 · 米亚 · 坦白放纵餐\n- 10-28 周三 08:00 发（米亚当地时间）\n- 写的：「炸鸡」\n- 照片 2 张，你还没看过（look_at_photos）',
        [
          '## 米亚',
          '- 今天的计划：力量',
          '- 这周练了：1 天',
          '- 这周发的：动态1 周二训练：跑步 30 分钟',
          '- 今天的挑战：「做深蹲 30 个」，接了，还没完成',
          '- 过去一天你们还在 动态1 下面聊过（post_comments 可看）',
          '- 你对米亚的了解（people/米亚.md）：\n```\n- 米亚爱吃炸鸡\n```',
        ].join('\n'),
        '## 小队的人\n米亚、里奥。小队的事、你和大家之间的事在 squad.md、memory.md，用 recall 查。',
        '## 你最近点过的表情\n🔥 💪',
        '## 他 App 的语言\n用简体中文写。',
      ].join('\n\n'),
    );
    // Who reacted and the comments under other posts are left out: looked up by number if needed.
    expect(task).not.toContain('点了表情');
    expect(task).not.toContain('「强」');
  });

  it('tells a comment’s reply the whole comment section, whom it answers, and no emoji', () => {
    const task = replyTaskOf(
      facts({
        kind: 'comment',
        post: run,
        to: leo,
        at: new Date('2026-10-27T13:00:00Z'),
        thread: {
          lines: [
            '- 你：「跑得好」',
            '- 10-27 周二 09:00 里奥（回复你）：「你也跑吗」（要回的这句）',
          ],
          mention: false,
        },
      }),
    );
    expect(task.split('\n\n').slice(0, 3)).toStrictEqual([
      '# 里奥在动态1下面回复你\n现在是 10-28 周三 08:05（小队时间）。',
      '## 动态1 · 米亚 · 训练：跑步 30 分钟\n- 10-27 周二 08:00 发（米亚当地时间）\n- 写的：「腿废了」',
      '## 评论区（先后顺序）\n- 你：「跑得好」\n- 10-27 周二 09:00 里奥（回复你）：「你也跑吗」（要回的这句）',
    ]);
    expect(task).toContain('## 里奥\n- 你对里奥的了解：还没记过。');
    expect(task).not.toContain('表情');
    expect(
      replyTaskOf(
        facts({ kind: 'comment', post: run, to: leo, thread: { lines: [], mention: true } }),
      ),
    ).toContain('# 里奥在动态1下面 @ 你');
  });

  it('says a 请假条’s streaks from two days on, and what is special about today', () => {
    const task = replyTaskOf(
      facts({
        keptStreaks: { training: 12, meals: 1 },
        today: ['感恩节', '你以前带过这个小队，被换掉后，现在又被请回来了。'],
      }),
    );
    expect(task).toContain('\n- 连续：训练 12 天（请假、休息、放纵餐那天不断，也不算一天）\n');
    expect(task).toContain(
      '\n\n## 今天\n- 感恩节\n- 你以前带过这个小队，被换掉后，现在又被请回来了。\n\n',
    );
    expect(replyTaskOf(facts({ keptStreaks: { training: 1 } }))).not.toContain('连续');
  });

  it('writes to a member in their app’s language', () => {
    const english: SquadWeek = {
      ...week,
      members: [{ member: mia, nickname: '米亚', language: 'en' }, { member: leo }],
    };
    expect(replyTaskOf(facts({ week: english, language: 'en' }))).toContain(
      '## 他 App 的语言\nWrite in English.',
    );
  });
});
