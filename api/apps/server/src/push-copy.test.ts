import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { PUSH_COPY } from './push-copy.js';
import { pushSamplesJson } from './push-samples.js';

// The app's String Catalog, which holds every push's words: a key the server sends that the
// catalog lacks shows on the phone as the bare key, `push.dailyProgress.poke`.
const catalogFile = new URL('../../../../ios/Wildcard/Localizable.xcstrings', import.meta.url);
const Catalog = z.object({
  strings: z.record(
    z.string(),
    z.object({
      localizations: z
        .record(z.string(), z.object({ stringUnit: z.object({ value: z.string() }).optional() }))
        .optional(),
    }),
  ),
});
const catalog = Catalog.parse(JSON.parse(readFileSync(catalogFile, 'utf8'))).strings;
const LANGUAGES = ['zh-Hans', 'en'];

/** The placeholders a line fills, by position: `%1$@ … %2$@` is [1, 2], and a bare `%@` counts in order. */
function placeholders(line: string): number[] {
  const found = [...line.matchAll(/%(?:(\d+)\$)?@/g)];
  return found.map((match, index) => (match[1] === undefined ? index + 1 : Number(match[1])));
}

describe('the push copy', () => {
  it.each(Object.entries(PUSH_COPY))(
    '%s has Chinese and English, each filling every placeholder once',
    (key, names) => {
      const expected = names.map((_, index) => index + 1);
      for (const language of LANGUAGES) {
        const line = catalog[key]?.localizations?.[language]?.stringUnit?.value;
        expect(line, `${key} has no ${language} line`).toBeTypeOf('string');
        expect(
          placeholders(line ?? '').sort((a, b) => a - b),
          `${key} in ${language}`,
        ).toEqual(expected);
      }
    },
  );

  it('leaves no push words in the app that the server never sends', () => {
    const inApp = Object.keys(catalog).filter((key) => key.startsWith('push.'));
    expect(inApp.sort()).toEqual(Object.keys(PUSH_COPY).sort());
  });

  it('has a current sample of every push for the app’s UI tests to deliver', () => {
    const committed = readFileSync(
      new URL('../../../../ios/WildcardUITests/push-samples.json', import.meta.url),
      'utf8',
    );
    expect(committed, 'run `pnpm push-samples` in api/').toBe(pushSamplesJson());
    const keys = Object.entries(
      z
        .record(
          z.string(),
          z.object({ aps: z.object({ alert: z.object({ 'loc-key': z.string() }) }) }),
        )
        .parse(JSON.parse(committed)),
    ).map(([name, sample]) => {
      expect(sample.aps.alert['loc-key']).toBe(name);
      return name;
    });
    expect(keys.sort()).toEqual(Object.keys(PUSH_COPY).sort());
  });
});
