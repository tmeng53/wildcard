import { Coach, CoachId } from '@wildcard/coach';
import type { ReaderLanguage } from '@wildcard/language-model';
import { MemberId as ProfileMember } from '@wildcard/members';
import { MemberId, SquadId } from '@wildcard/squads';
import { describe, expect, it } from 'vitest';

import { card } from '../routes/squad-coach.js';
import { coachNamesIn } from './coach-names.js';

const poki = Coach.parse({
  version: 3,
  id: CoachId.parse('xiaohun'),
  position: 1,
  tier: 'entry',
  name: '毛头',
  title: '混混教练',
  catchphrase: '先动起来，证书以后再说',
  background: '体育学院刚毕业',
  yearsCoaching: 0,
  experience: '热情满格',
  style: '懂行、松弛、风趣',
  tags: ['体院应届', '懂行'],
  pay: '管饭就行',
  soul: '你是毛头。',
  look: 'xiaohun',
  offered: true,
  translations: {
    'zh-Hant': {
      name: '毛頭',
      title: '混混教練',
      catchphrase: '先動起來，證照以後再說',
      background: '體育系剛畢業',
      experience: '熱情滿點',
      style: '內行、隨性、幽默',
      tags: ['體育系新鮮人', '內行'],
      pay: '有飯吃就好',
    },
    en: {
      name: 'Poki',
      title: 'Couch Coach',
      catchphrase: 'Move first, certificates later',
      background: 'Fresh kinesiology grad',
      experience: 'All heart',
      style: 'Knows the stuff, chill, funny',
      tags: ['Fresh grad', 'Knows stuff'],
      pay: 'Will work for food',
    },
  },
});

const english = SquadId.parse('5c1f3a2e-0b4d-4e6f-8a9b-1c2d3e4f5a6b');
const taiwan = SquadId.parse('6d2f4b3e-1c5d-4f6a-9b8c-2d3e4f5a6b7c');
const ended = SquadId.parse('7e3a5c4f-2d6e-4a7b-8c9d-3e4f5a6b7c8d');
const captains = new Map([
  [english, MemberId.parse('0a5c1f2e-3b4d-4e6f-8a9b-1c2d3e4f5a6b')],
  [taiwan, MemberId.parse('1b6d2f3e-4c5d-4f6a-9b8c-2d3e4f5a6b7c')],
]);
const spoken = new Map<string, ReaderLanguage>([
  ['0a5c1f2e-3b4d-4e6f-8a9b-1c2d3e4f5a6b', 'en'],
  ['1b6d2f3e-4c5d-4f6a-9b8c-2d3e4f5a6b7c', 'zh-Hant'],
]);

const names = coachNamesIn({
  coaches: { list: () => Promise.resolve([poki]) },
  members: {
    languages: (members) =>
      Promise.resolve(
        new Map(
          members.flatMap((member) => {
            const language = spoken.get(member);
            return language === undefined ? [] : [[ProfileMember.parse(member), language] as const];
          }),
        ),
      ),
  },
  squads: { captainOf: (squad) => Promise.resolve(captains.get(squad)) },
});

describe('a coach’s name', () => {
  it('is the one in its squad’s language, its captain’s', async () => {
    const named = await names([
      { coach: 'xiaohun', squad: english },
      { coach: 'xiaohun', squad: taiwan },
      { coach: 'xiaohun', squad: ended },
    ]);
    expect([
      named('xiaohun', english),
      named('xiaohun', taiwan),
      named('xiaohun', ended),
      named('xiaohun', undefined),
      named('gone', english),
    ]).toStrictEqual(['Poki', '毛頭', '毛头', '毛头', undefined]);
  });

  it('falls back to the stored one, never failing, when it can’t be looked up', async () => {
    const failing = coachNamesIn({
      coaches: { list: () => Promise.resolve([poki]) },
      members: { languages: () => Promise.reject(new Error('down')) },
      squads: { captainOf: (squad) => Promise.resolve(captains.get(squad)) },
    });
    expect((await failing([{ coach: 'xiaohun', squad: english }]))('xiaohun', english)).toBe(
      '毛头',
    );
    const noCatalog = coachNamesIn({
      coaches: { list: () => Promise.reject(new Error('down')) },
      members: { languages: () => Promise.resolve(new Map()) },
      squads: { captainOf: () => Promise.resolve(undefined) },
    });
    expect((await noCatalog([{ coach: 'xiaohun', squad: english }]))('xiaohun', english)).toBe(
      undefined,
    );
  });

  it('heads a 简历 in the reader’s language', () => {
    expect(card(poki, { reader: 'zh-Hans', squad: 'en' })).toStrictEqual({
      id: 'xiaohun',
      tier: 'entry',
      name: 'Poki',
      title: '混混教练',
      catchphrase: '先动起来，证书以后再说',
      background: '体育学院刚毕业',
      yearsCoaching: 0,
      experience: '热情满格',
      style: '懂行、松弛、风趣',
      tags: ['体院应届', '懂行'],
      pay: '管饭就行',
      look: 'xiaohun',
    });
    expect(card(poki, { reader: 'en', squad: 'en' })).toMatchObject({
      name: 'Poki',
      title: 'Couch Coach',
      tags: ['Fresh grad', 'Knows stuff'],
      pay: 'Will work for food',
    });
  });
});
