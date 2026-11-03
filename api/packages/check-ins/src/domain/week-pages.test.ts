import { describe, expect, it } from 'vitest';

import { podiumOf } from './week-pages.js';

/** A member who trained `days[0]` days of a plan of `days[1]` (5 unless given). */
const member = (id: string, [trainedDays, plannedDays = 5]: readonly [number, number?]) => ({
  member: id,
  trainedDays,
  plannedDays,
});

describe('the podium', () => {
  it('stands the top 3 by days trained on it, the most in the middle, plan finished or not', () => {
    expect(
      podiumOf([
        member('a', [1]),
        member('b', [4]),
        member('c', [4]),
        member('d', [2]),
        member('e', [0]),
      ]),
    ).toStrictEqual({ champion: 'b', sides: ['c', 'd'], planDone: [] });
  });

  it('marks those on it who trained every day they planned', () => {
    expect(
      podiumOf([
        member('a', [2, 2]),
        member('b', [3, 5]),
        member('c', [1, 1]),
        member('d', [1, 0]),
      ]),
    ).toStrictEqual({ champion: 'b', sides: ['a', 'c'], planDone: ['a', 'c'] });
  });

  it('keeps the earliest to join first on a tie', () => {
    expect(
      podiumOf([member('a', [3]), member('b', [3]), member('c', [3]), member('d', [3])]),
    ).toStrictEqual({ champion: 'a', sides: ['b', 'c'], planDone: [] });
  });

  it('is missing when nobody trained, and stands one member alone', () => {
    expect(podiumOf([member('a', [0]), member('b', [0])])).toBeUndefined();
    expect(podiumOf([member('a', [1, 1])])).toStrictEqual({
      champion: 'a',
      sides: [],
      planDone: ['a'],
    });
  });
});
