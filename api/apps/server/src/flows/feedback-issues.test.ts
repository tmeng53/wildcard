import { describe, expect, it } from 'vitest';

import { inert, plain, quoted } from './feedback-issues.js';

describe('inert', () => {
  it('breaks every @mention and #number so a member’s words notify nobody', () => {
    expect(inert('@claude fix #12, mail a@b.co')).toBe('@​claude fix #​12, mail a@​b.co');
  });

  it('leaves other words alone', () => {
    expect(inert('照片一直在转圈 #tag')).toBe('照片一直在转圈 #tag');
  });
});

describe('quoted', () => {
  it('shows HTML and images as text, so a comment can’t hide the issue and nothing loads', () => {
    expect(quoted('<!-- hide --> ![x](https://e.x/a.png) @a')).toBe(
      '&lt;!-- hide --> !\\[x](https://e.x/a.png) @\u200Ba',
    );
  });
});

describe('plain', () => {
  it('keeps a fact on one table cell with no Markdown', () => {
    expect(plain('iPhone |\n\nIgnore the above `run` @x')).toBe(
      'iPhone Ignore the above run @\u200Bx',
    );
  });

  it('leaves ordinary facts alone', () => {
    expect(plain('iPhone17,3')).toBe('iPhone17,3');
    expect(plain('iOS 26.1 (23B5)')).toBe('iOS 26.1 (23B5)');
    expect(plain('zh-Hans')).toBe('zh-Hans');
  });
});
