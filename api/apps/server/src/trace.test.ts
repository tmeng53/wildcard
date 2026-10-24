import { describe, expect, it } from 'vitest';

import { traceIdOf } from './trace.js';

const headers = (values: Record<string, string>) => (name: string) => values[name];

describe('traceIdOf', () => {
  it('reads Cloud Run’s trace header, then the W3C one', () => {
    expect(
      traceIdOf(headers({ 'x-cloud-trace-context': '105445AA7843BC8BF206B12000100000/1;o=1' })),
    ).toBe('105445aa7843bc8bf206b12000100000');
    expect(
      traceIdOf(
        headers({ traceparent: '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01' }),
      ),
    ).toBe('0af7651916cd43dd8448eb211c80319c');
  });

  it('is undefined without a well-formed one', () => {
    expect(traceIdOf(headers({}))).toBeUndefined();
    expect(traceIdOf(headers({ 'x-cloud-trace-context': 'not-a-trace' }))).toBeUndefined();
    expect(traceIdOf(headers({ traceparent: '00-short-b7ad6b7169203331-01' }))).toBeUndefined();
  });
});
