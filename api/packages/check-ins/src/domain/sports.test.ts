import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { SPORTS } from './sports.js';

// The app's contract is the source of the list; this reads it rather than trusting a copy.
const swift = readFileSync(
  new URL('../../../../../ios/Packages/Contracts/Sources/Contracts/Sport.swift', import.meta.url),
  'utf8',
);

describe('SPORTS', () => {
  it('lists exactly the contract’s sports, in its order', () => {
    const body = /public enum Sport\b[^{]*\{([\s\S]*?)\n {4}public var category/.exec(swift)?.[1];
    const cases = [...(body ?? '').matchAll(/^\s*case (.+)$/gm)].flatMap((match) =>
      (match[1] ?? '').split(',').map((name) => name.trim()),
    );
    expect(cases).toStrictEqual([...SPORTS]);
    expect(SPORTS).toHaveLength(52);
  });
});
