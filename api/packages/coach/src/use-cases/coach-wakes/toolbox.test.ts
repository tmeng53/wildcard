import { describe, expect, it } from 'vitest';

import { mentioning } from './toolbox.js';

const mia = '00000000-0000-4000-8000-000000000001';
const miao = '00000000-0000-4000-8000-000000000002';
const context = {
  week: {
    members: [
      { member: mia, nickname: 'Mia' },
      { member: miao, nickname: 'Miao' },
    ],
  },
  roster: new Map([
    [mia, '队员1'],
    [miao, '队员2'],
  ]),
};

describe('mentioning', () => {
  it('puts a space after a nickname the line already @s, so the app sees where it ends', () => {
    expect(mentioning({ line: '@Mia加油，@Mia 冲', at: ['队员1'] }, context)).toEqual({
      line: '@Mia 加油，@Mia 冲',
      mentions: [mia],
    });
  });

  it('leaves a longer name that starts with the nickname as it is', () => {
    expect(mentioning({ line: '@Miao加油 @Mia', at: ['队员1'] }, context)).toEqual({
      line: '@Miao加油 @Mia',
      mentions: [mia],
    });
  });

  it('starts the line with the @ when the line leaves it out', () => {
    expect(mentioning({ line: '今天冲', at: ['队员1'] }, context)).toEqual({
      line: '@Mia 今天冲',
      mentions: [mia],
    });
  });
});
