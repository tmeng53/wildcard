import { describe, expect, it } from 'vitest';

import { randomInviteCodes } from '../adapters/random-invite-codes.js';
import { InviteCode } from './invite-code.js';

describe('InviteCode', () => {
  it.each([
    ['K7M2QX9P', 'K7M2QX9P'],
    ['k7m2qx9p', 'K7M2QX9P'],
    ['K7M2-QX9P', 'K7M2QX9P'],
    [' k7m2 qx9p ', 'K7M2QX9P'],
  ])('reads %j as %j', (typed, code) => {
    expect(InviteCode.parse(typed)).toBe(code);
  });

  it.each(['K7M2QX9', 'K7M2QX9PP', 'K7M2QX0P', 'K7M2QXOP', 'K7M2QX1P', 'K7M2QXIP', 'K7M2QXLP', ''])(
    'refuses %j',
    (typed) => {
      expect(InviteCode.safeParse(typed).success).toBe(false);
    },
  );
});

describe('randomInviteCodes', () => {
  it('makes valid codes that differ', () => {
    const codes = Array.from({ length: 200 }, () => randomInviteCodes());
    expect(codes.every((code) => InviteCode.safeParse(code).success)).toBe(true);
    expect(new Set(codes).size).toBe(200);
  });
});
