import { describe, expect, it } from 'vitest';

import { challengeTaskOf } from './challenge-task.js';
import type { WeekCheckIn } from './squad-week.js';

const ANN = '00000000-0000-4000-8000-00000000000a';
const BO = '00000000-0000-4000-8000-00000000000b';

const post = (
  each: Partial<WeekCheckIn> & Pick<WeekCheckIn, 'id' | 'member' | 'day' | 'kind'>,
): WeekCheckIn => ({ createdAt: new Date(0), reactedBy: [], comments: [], ...each });

describe('the task that sets the day’s challenges', () => {
  it('gives each member their plan, posts by number, recent challenges and what is known', () => {
    const names = new Map([
      [ANN, '安'],
      [BO, '波'],
    ]);
    const { task, numbered } = challengeTaskOf({
      day: '2026-11-14',
      names,
      members: [
        {
          member: ANN,
          brief: {
            name: '队员1',
            trainedDays: 1,
            plan: {
              week: [
                { kind: 'train', sport: '跑步' },
                { kind: 'rest' },
                { kind: 'rest' },
                { kind: 'rest' },
                { kind: 'rest' },
                { kind: 'train', sport: '匹克球' },
                { kind: 'rest' },
              ],
              fuelGoals: ['多吃蔬菜'],
            },
            weather: { words: '今天下雨', city: '纽约' },
          },
          about: '- 安想增肌。',
        },
        { member: BO, brief: { name: '队员2', trainedDays: 0, language: 'en' } },
      ],
      posts: [
        post({
          id: 'a1',
          member: ANN,
          day: '2026-11-13',
          kind: 'trained',
          sport: '篮球',
          minutes: 15,
          text: '打篮球也是练了',
          comments: [{ id: 'c1', member: BO, text: '厉害', at: new Date(0) }],
        }),
        post({ id: 'b1', member: BO, day: '2026-11-13', kind: 'cheatMeal', unposted: true }),
      ],
      challenges: [
        {
          day: '2026-11-13',
          member: ANN,
          challenge: { title: '做深蹲', amount: 50, unit: '个' },
          answer: 'declined',
          reason: '膝盖不舒服',
          completion: undefined,
        },
      ],
    });
    expect(task).toBe(
      [
        '今天是 2026-11-14，周六。',
        [
          '## 安',
          '- 今天的计划：匹克球',
          '- 这周出赛表：周一跑步，周二休息，周三休息，周四休息，周五休息，周六匹克球，周日休息',
          '- 这周饮食小目标：多吃蔬菜',
          '- 这周练了：1 天',
          '- 最近发的：',
          '  - 动态1 · 11-13 周五 篮球 15 分钟：「打篮球也是练了」（1 条评论）',
          '- 最近的挑战：',
          '  - 11-13 周五「做深蹲 50 个」：没接，理由：「膝盖不舒服」（只告诉了你）',
          '- 当地天气：纽约，今天下雨',
          '- 你对他的了解：\n- 安想增肌。',
          '- 用简体中文写。',
        ].join('\n'),
        [
          '## 波',
          '- 今天的计划：没填出赛表',
          '- 这周练了：0 天',
          '- 最近发的：',
          '  - 动态2 · 11-13 周五 坦白放纵餐（只记录，没发动态）',
          '- Write in English.',
        ].join('\n'),
      ].join('\n\n'),
    );
    expect([...numbered.keys()]).toStrictEqual(['动态1', '动态2']);
    expect(numbered.get('动态1')?.id).toBe('a1');
  });
});
