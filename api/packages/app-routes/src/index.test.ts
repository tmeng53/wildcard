import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { APP_ROUTES, AppAddress, routeOf, routesJson } from './index.js';

describe('AppAddress', () => {
  it('takes every route’s sample, with or without the scheme', () => {
    for (const route of APP_ROUTES) {
      expect(AppAddress.safeParse(route.sample).success).toBe(true);
      expect(AppAddress.safeParse(`wildcard://${route.sample}`).success).toBe(true);
      expect(routeOf(route.sample)?.pattern).toBe(route.pattern);
    }
  });

  it('takes the places broadcasts already open', () => {
    for (const place of [
      'stores',
      'store/powder',
      'schedule',
      'squad',
      'coaches',
      'feed',
      'today',
      'me',
      'wardrobe',
      'wardrobe/thanks-bulb',
      'badges',
      'notices',
    ]) {
      expect(AppAddress.safeParse(place).success).toBe(true);
    }
  });

  it('refuses a place the app has no page for', () => {
    for (const place of [
      'coaches/xiaohun',
      'wardrobe/',
      'badges/idea-king',
      'post/not-a-uuid',
      'recap/last-week',
      'store/powder/extra',
      'https://example.com',
      '',
    ]) {
      expect(AppAddress.safeParse(place).success).toBe(false);
    }
  });

  it('has one route a pattern', () => {
    expect(new Set(APP_ROUTES.map((route) => route.pattern)).size).toBe(APP_ROUTES.length);
  });
});

describe('routes.json', () => {
  it('is current (pnpm --dir api app-routes rewrites it)', () => {
    const file = readFileSync(new URL('../routes.json', import.meta.url), 'utf8');
    expect(file).toBe(routesJson());
  });
});
