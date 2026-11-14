import { describe, expect, it } from 'vitest';

import { CardPath, MessageValue, cardsOf, isFor, isRunning, refusal } from './message.js';

const words = (zhHans: string) => ({ zhHans, en: zhHans, zhHant: zhHans });

/** 喜欢外卡吗？ 喜欢 → 写个评价？ (写评价 opens the App Store) | 不太喜欢 → 哪里不好用？ (a box). */
const enjoying = {
  version: 1,
  card: {
    line: words('喜欢外卡吗？'),
    buttons: [
      {
        id: 'yes',
        label: words('喜欢'),
        style: 'primary',
        tap: [
          {
            next: {
              line: words('给外卡写个评价？'),
              buttons: [
                {
                  id: 'review',
                  label: words('写评价'),
                  tap: [
                    { open: 'https://apps.apple.com/app/id1?action=write-review' },
                    { close: true },
                  ],
                },
              ],
              thanks: words('谢谢你！'),
            },
          },
        ],
      },
      {
        id: 'no',
        label: words('不太喜欢'),
        tap: [
          {
            next: {
              line: words('哪里不好用？'),
              input: {},
              buttons: [
                {
                  id: 'send',
                  label: words('发送'),
                  tap: [{ feedback: 'problem' }, { close: true }],
                },
              ],
            },
          },
        ],
      },
    ],
  },
  startsAt: '2026-11-14T00:00:00Z',
};

const message = MessageValue.parse(enjoying);
const path = (value: string) => CardPath.parse(value);

describe('a coach message', () => {
  it('lists every card of its tree by the buttons tapped to reach it', () => {
    expect([...cardsOf(message.card).keys()]).toStrictEqual(['', 'yes', 'no']);
  });

  it('refuses `feedback` on a card with no box, two ways out of one tap, a button twice', () => {
    const refused = (card: object) =>
      MessageValue.safeParse({ ...enjoying, card }).error?.issues.map((issue) => issue.message);
    expect(
      refused({
        line: words('嗨'),
        buttons: [{ id: 'a', label: words('好'), tap: [{ feedback: 'idea' }] }],
      }),
    ).toStrictEqual(['`feedback` sends the box’s words, so the card needs an `input`']);
    expect(
      refused({
        line: words('嗨'),
        buttons: [{ id: 'a', label: words('好'), tap: [{ close: true }, { close: true }] }],
      }),
    ).toStrictEqual(['a tap turns to one `next` or `close`s, once']);
    expect(
      refused({
        line: words('嗨'),
        buttons: [
          { id: 'a', label: words('好'), tap: [{ close: true }] },
          { id: 'a', label: words('好'), tap: [{ close: true }] },
        ],
      }),
    ).toStrictEqual(['each button’s id once']);
  });

  it('goes three cards deep at most', () => {
    const deep = (card: object) => ({
      line: words('嗨'),
      buttons: [{ id: 'a', label: words('好'), tap: [{ next: card }] }],
    });
    const last = { line: words('嗨') };
    expect(MessageValue.safeParse({ ...enjoying, card: deep(deep(last)) }).success).toBe(true);
    expect(MessageValue.safeParse({ ...enjoying, card: deep(deep(deep(last))) }).success).toBe(
      false,
    );
  });

  it('opens only a page in the app or an https page', () => {
    const opening = (open: string) =>
      MessageValue.safeParse({
        ...enjoying,
        card: {
          line: words('嗨'),
          buttons: [{ id: 'a', label: words('去'), tap: [{ open }] }],
        },
      }).success;
    expect(opening('store/powder')).toBe(true);
    expect(opening('https://wildcardsquad.com')).toBe(true);
    expect(opening('http://wildcardsquad.com')).toBe(false);
    expect(opening('wildcard://store/powder')).toBe(false);
  });

  it('runs from its start until its end, for everyone or the members it names', () => {
    const named = MessageValue.parse({
      ...enjoying,
      members: ['0A1B2C3D-0000-4000-8000-000000000001'],
      endsAt: '2026-11-15T00:00:00Z',
    });
    expect(isRunning(named, new Date('2026-11-13T23:59:59Z'))).toBe(false);
    expect(isRunning(named, new Date('2026-11-14T00:00:00Z'))).toBe(true);
    expect(isRunning(named, new Date('2026-11-15T00:00:00Z'))).toBe(false);
    expect(isFor(named, '0a1b2c3d-0000-4000-8000-000000000001')).toBe(true);
    expect(isFor(named, '0a1b2c3d-0000-4000-8000-000000000002')).toBe(false);
    expect(isFor(message, '0a1b2c3d-0000-4000-8000-000000000002')).toBe(true);
  });

  it('takes an answer only on a card reached, and only a part that card has', () => {
    const none = new Map();
    const saidNo = new Map([[path(''), { tap: 'no' }]]);
    expect(
      refusal(message, { answered: none, path: path(''), part: { part: 'tap', button: 'yes' } }),
    ).toBeUndefined();
    expect(
      refusal(message, { answered: none, path: path(''), part: { part: 'tap', button: 'maybe' } }),
    ).toBe('no such button');
    expect(
      refusal(message, { answered: none, path: path(''), part: { part: 'stars', stars: 5 } }),
    ).toBe('it has no stars');
    expect(
      refusal(message, { answered: none, path: path(''), part: { part: 'text', text: '嗯' } }),
    ).toBe('it has no box to type in');
    expect(
      refusal(message, { answered: none, path: path('no'), part: { part: 'text', text: '太慢' } }),
    ).toBe('its button wasn’t tapped');
    expect(
      refusal(message, {
        answered: saidNo,
        path: path('no'),
        part: { part: 'text', text: '太慢' },
      }),
    ).toBeUndefined();
    expect(
      refusal(message, {
        answered: saidNo,
        path: path('yes'),
        part: { part: 'tap', button: 'review' },
      }),
    ).toBe('its button wasn’t tapped');
    expect(
      refusal(message, {
        answered: saidNo,
        path: path('maybe'),
        part: { part: 'tap', button: 'x' },
      }),
    ).toBe('no such card');
  });
});
