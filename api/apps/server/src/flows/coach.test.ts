import { readFileSync } from 'node:fs';

import { FuelSuggestion } from '@wildcard/check-ins';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { FUEL_WORDS } from './coach.js';

// The coach reads a suggested 饮食小目标 in the words the member picked it by, so they stay the
// app's: ScheduleUI's String Catalog, `fuel.<suggestion>`, in Simplified Chinese.
const catalogFile = new URL(
  '../../../../../ios/Packages/Schedule/Sources/ScheduleUI/Resources/Localizable.xcstrings',
  import.meta.url,
);
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

describe('the coach’s 饮食小目标 words', () => {
  it.each(FuelSuggestion.options)('%s reads as the app shows it', (suggestion) => {
    expect(FUEL_WORDS[suggestion]).toBe(
      catalog[`fuel.${suggestion}`]?.localizations?.['zh-Hans']?.stringUnit?.value,
    );
  });
});
