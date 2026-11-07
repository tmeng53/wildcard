import { describe, expect, it } from 'vitest';

import { BadgeCatalog, shownBadge, withSportGlyphs } from './badges.js';

const catalog = BadgeCatalog.parse({
  shapes: [{ id: 'circle', meaning: '圆' }],
  colours: [
    { id: 'track', tone: '#E65345', meaning: '红' },
    { id: 'lavender', tone: '#9062DE', meaning: '薰衣草' },
  ],
  glyphs: [{ id: 'figure.run', meaning: '跑步的人：跑步、有氧' }],
});

describe('withSportGlyphs', () => {
  it('adds each sport’s icon once after the settings’ glyphs, keeping their meaning', () => {
    const offered = withSportGlyphs(catalog, [
      { id: 'figure.run', meaning: '跑步（运动）' },
      { id: 'figure.yoga', meaning: '瑜伽（运动）' },
      { id: 'figure.yoga', meaning: '普拉提（运动）' },
      { id: 'Not A Symbol', meaning: '坏的' },
    ]);
    expect(offered.glyphs).toStrictEqual([
      { id: 'figure.run', meaning: '跑步的人：跑步、有氧' },
      { id: 'figure.yoga', meaning: '瑜伽（运动）' },
    ]);
    expect(offered.colours).toBe(catalog.colours);
  });
});

describe('shownBadge', () => {
  it('paints a badge in its colour’s tone, and the gym’s steel for a colour no longer listed', () => {
    expect(
      shownBadge({ shape: 'circle', colour: 'lavender', glyph: 'moon.fill' }, catalog),
    ).toStrictEqual({
      shape: 'circle',
      colour: 'lavender',
      glyph: 'moon.fill',
      tone: '#9062DE',
    });
    expect(shownBadge({ shape: 'circle', colour: 'gone', glyph: 'moon.fill' }, catalog).tone).toBe(
      '#4A6C8C',
    );
  });
});

describe('BadgeCatalog', () => {
  it('takes a tone only as #RRGGBB', () => {
    const colours = [{ id: 'track', tone: '#e65345', meaning: '红' }];
    expect(BadgeCatalog.safeParse({ ...catalog, colours }).success).toBe(false);
  });
});
