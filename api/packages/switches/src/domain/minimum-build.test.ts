import { describe, expect, it } from 'vitest';

import { BuildNumber, MinimumBuild } from './minimum-build.js';

describe('the minimum build', () => {
  it('takes the build numbers TestFlight gives, and nothing else', () => {
    expect(BuildNumber.safeParse('190').success).toBe(true);
    expect(BuildNumber.safeParse('190.1').success).toBe(true);
    expect(BuildNumber.safeParse('190.1.2').success).toBe(true);
    expect(BuildNumber.safeParse('v190').success).toBe(false);
    expect(BuildNumber.safeParse('190.').success).toBe(false);
    expect(BuildNumber.safeParse('1.2.3.4').success).toBe(false);
    expect(MinimumBuild.safeParse({ version: 1, build: null }).success).toBe(true);
  });
});
