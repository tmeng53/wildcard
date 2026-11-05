import { describe, expect, it } from 'vitest';

import { podiumOf } from './week-pages.js';

/** A member who trained `days[0]` days of a plan of `days[1]` (5 unless given), finishing it at `days[2]`. */
const member = (
  id: string,
  [trainedDays, plannedDays = 5, planFinishedAt]: readonly [number, number?, string?],
) => ({
  member: id,
  trainedDays,
  plannedDays,
  planFinishedAt,
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
    ).toStrictEqual({ champion: 'b', sides: ['c', 'd'], planDone: [], tieBrokenByPlan: false });
  });

  it('marks those on it who trained every day they planned', () => {
    expect(
      podiumOf([
        member('a', [2, 2]),
        member('b', [3, 5]),
        member('c', [1, 1]),
        member('d', [1, 0]),
      ]),
    ).toStrictEqual({
      champion: 'b',
      sides: ['a', 'c'],
      planDone: ['a', 'c'],
      tieBrokenByPlan: false,
    });
  });

  it('keeps the earliest to join first on a tie', () => {
    expect(
      podiumOf([member('a', [3]), member('b', [3]), member('c', [3]), member('d', [3])]),
    ).toStrictEqual({ champion: 'a', sides: ['b', 'c'], planDone: [], tieBrokenByPlan: false });
  });

  it('is missing when nobody trained, and stands one member alone', () => {
    expect(podiumOf([member('a', [0]), member('b', [0])])).toBeUndefined();
    expect(podiumOf([member('a', [1, 1])])).toStrictEqual({
      champion: 'a',
      sides: [],
      planDone: ['a'],
      tieBrokenByPlan: false,
    });
  });

  it('gives a tie to whoever finished their own plan first, not whoever joined first', () => {
    expect(
      podiumOf([
        member('captain', [3, 3, '2026-10-23T18:00:00.000Z']),
        member('second', [3, 3, '2026-10-21T09:00:00.000Z']),
        member('third', [3, 5]),
        member('fourth', [3, 3, '2026-10-22T09:00:00.000Z']),
      ]),
    ).toStrictEqual({
      champion: 'second',
      sides: ['fourth', 'captain'],
      planDone: ['second', 'fourth', 'captain'],
      tieBrokenByPlan: true,
    });
  });

  it('says so only when the plan decided a place, and keeps the join order among the rest', () => {
    // The champion trained more days: no tie to break.
    expect(
      podiumOf([
        member('a', [4, 3, '2026-10-23T18:00:00.000Z']),
        member('b', [3, 3, '2026-10-20T09:00:00.000Z']),
      ]),
    ).toMatchObject({ champion: 'a', sides: ['b'], tieBrokenByPlan: false });
    // Nobody finished: join order, and nothing to say about the plan.
    expect(podiumOf([member('a', [2, 5]), member('b', [2, 5])])).toMatchObject({
      champion: 'a',
      sides: ['b'],
      tieBrokenByPlan: false,
    });
    // The one who finished beats those who didn't, though they joined last.
    expect(
      podiumOf([
        member('a', [3, 5]),
        member('b', [3, 5]),
        member('c', [3, 5]),
        member('d', [3, 3, '2026-10-22T09:00:00.000Z']),
      ]),
    ).toMatchObject({ champion: 'd', sides: ['a', 'b'], tieBrokenByPlan: true });
  });
});
