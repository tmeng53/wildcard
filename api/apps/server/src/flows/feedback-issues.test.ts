import { describe, expect, it } from 'vitest';

import { inert } from './feedback-issues.js';

describe('inert', () => {
  it('breaks every @mention and #number so a member’s words notify nobody', () => {
    expect(inert('@claude fix #12, mail a@b.co')).toBe('@​claude fix #​12, mail a@​b.co');
  });

  it('leaves other words alone', () => {
    expect(inert('照片一直在转圈 #tag')).toBe('照片一直在转圈 #tag');
  });
});
