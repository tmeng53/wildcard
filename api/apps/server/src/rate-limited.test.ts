import { describe, expect, it } from 'vitest';

import { clientAddress } from './rate-limited.js';

describe('the client address', () => {
  it.each([
    { header: '203.0.113.7', hops: 1, address: '203.0.113.7' },
    // A client can write its own entries; only the ones our proxies add are trusted.
    { header: '1.1.1.1, 203.0.113.7', hops: 1, address: '203.0.113.7' },
    { header: '1.1.1.1, 203.0.113.7, 10.0.0.1', hops: 2, address: '203.0.113.7' },
    { header: '203.0.113.7', hops: 2, address: 'unknown' },
    { header: undefined, hops: 1, address: 'unknown' },
    { header: '', hops: 1, address: 'unknown' },
  ])('of $header with $hops proxy hops is $address', ({ header, hops, address }) => {
    expect(clientAddress(header, hops)).toBe(address);
  });
});
