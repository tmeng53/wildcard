import { generateKeyPairSync, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { describe, expect, it } from 'vitest';

import { createWeatherKitForecasts } from './weatherkit-forecasts.js';

// WeatherKit's daily forecast as its REST API documents it, trimmed to two days. Replayed,
// never a live call.
const DAILY = readFileSync(new URL('fixtures/weatherkit-daily.json', import.meta.url), 'utf8');

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const ACCOUNT = {
  teamId: 'TEAM123456',
  serviceId: 'com.wildcardsquad.wildcard',
  keyId: 'KEY1234567',
  privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
};

function replaying(status = 200) {
  const requests: { url: string; authorization: string | null }[] = [];
  const fetch: typeof globalThis.fetch = (input, init) => {
    requests.push({
      url: input instanceof Request ? input.url : input.toString(),
      authorization: new Headers(init?.headers).get('authorization'),
    });
    return Promise.resolve(new Response(DAILY, { status }));
  };
  return { fetch, requests };
}

const decode = (part: string): unknown => JSON.parse(Buffer.from(part, 'base64url').toString());

describe('createWeatherKitForecasts', () => {
  it('reads the day asked for, on the member’s clock', async () => {
    const { fetch, requests } = replaying();
    const forecasts = createWeatherKitForecasts(ACCOUNT, { fetch, now: () => 1_794_000_000_000 });
    const day = await forecasts.dayAt({
      place: { latitude: 40.7, longitude: -74 },
      day: '2026-11-09',
      timeZone: 'America/New_York',
    });
    expect(day).toStrictEqual({
      version: 1,
      condition: 'Rain',
      high: 12.8,
      low: 7.9,
      precipitationChance: 0.82,
    });
    expect(requests.map(({ url }) => url)).toStrictEqual([
      'https://weatherkit.apple.com/api/v1/weather/en/40.7/-74?dataSets=forecastDaily&timezone=America%2FNew_York',
    ]);
  });

  it('signs in with the developer token WeatherKit takes', async () => {
    const { fetch, requests } = replaying();
    await createWeatherKitForecasts(ACCOUNT, { fetch, now: () => 1_794_000_000_000 }).dayAt({
      place: { latitude: 40.7, longitude: -74 },
      day: '2026-11-08',
      timeZone: 'America/New_York',
    });
    const token = requests[0]?.authorization?.replace('Bearer ', '') ?? '';
    const [header = '', payload = '', signature = ''] = token.split('.');
    expect(decode(header)).toStrictEqual({
      alg: 'ES256',
      kid: 'KEY1234567',
      id: 'TEAM123456.com.wildcardsquad.wildcard',
    });
    expect(decode(payload)).toStrictEqual({
      iss: 'TEAM123456',
      iat: 1_794_000_000,
      exp: 1_794_003_600,
      sub: 'com.wildcardsquad.wildcard',
    });
    expect(
      verify(
        'sha256',
        Buffer.from(`${header}.${payload}`),
        { key: publicKey, dsaEncoding: 'ieee-p1363' },
        Buffer.from(signature, 'base64url'),
      ),
    ).toBe(true);
  });

  it('has nothing for a day outside the forecast', async () => {
    const { fetch } = replaying();
    const day = await createWeatherKitForecasts(ACCOUNT, { fetch }).dayAt({
      place: { latitude: 40.7, longitude: -74 },
      day: '2026-12-25',
      timeZone: 'America/New_York',
    });
    expect(day).toBeUndefined();
  });

  it('throws when WeatherKit refuses', async () => {
    const { fetch } = replaying(401);
    await expect(
      createWeatherKitForecasts(ACCOUNT, { fetch }).dayAt({
        place: { latitude: 40.7, longitude: -74 },
        day: '2026-11-09',
        timeZone: 'America/New_York',
      }),
    ).rejects.toThrow('WeatherKit answered 401');
  });
});
