import { describe, expect, it } from 'vitest';

import { mentioning } from './toolbox.js';

const mia = '00000000-0000-4000-8000-000000000001';
const context = {
  week: { members: [{ member: mia, nickname: 'Mia' }] },
  roster: new Map([[mia, '队员1']]),
};

describe('mentioning', () => {
  it('puts a space after a nickname the line already @s, so the app sees where it ends', () => {
    expect(mentioning({ line: '@Mia加油，@Mia 冲', at: ['队员1'] }, context)).toEqual({
      line: '@Mia 加油，@Mia 冲',
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
