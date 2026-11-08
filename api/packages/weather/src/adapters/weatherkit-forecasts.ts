import { createPrivateKey, sign, type KeyObject } from 'node:crypto';

import { z } from 'zod';

import type { DayWeather } from '../domain/day-weather.js';
import type { Forecasts } from '../ports.js';

/** The WeatherKit key, made in Apple Developer with WeatherKit ticked. */
export interface WeatherKitAccount {
  /** The Apple Developer Team ID. */
  readonly teamId: string;
  /** The identifier WeatherKit is enabled for (the app's bundle id). */
  readonly serviceId: string;
  /** The 10-character Key ID Apple shows for the `.p8` key. */
  readonly keyId: string;
  /** The `.p8` file's contents (a PEM EC private key). */
  readonly privateKey: string;
}

const ORIGIN = 'https://weatherkit.apple.com';
/** WeatherKit takes a token for up to an hour; a new one is signed after 50 minutes. */
const TOKEN_LIFETIME_S = 60 * 60;
const TOKEN_REFRESH_MS = 50 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 10_000;

// Only what we read; WeatherKit sends much more, and adds fields over time.
const DailyForecast = z.object({
  forecastDaily: z
    .object({
      days: z.array(
        z.object({
          forecastStart: z.string(),
          conditionCode: z.string().min(1).max(64).optional(),
          temperatureMax: z.number(),
          temperatureMin: z.number(),
          precipitationChance: z.number().min(0).max(1).optional(),
        }),
      ),
    })
    .optional(),
});

/** Apple WeatherKit's REST API as the weather provider. */
export function createWeatherKitForecasts(
  account: WeatherKitAccount,
  {
    fetch: fetchFn = fetch,
    now = () => Date.now(),
  }: {
    readonly fetch?: typeof fetch;
    readonly now?: () => number;
  } = {},
): Forecasts {
  const key = createPrivateKey(account.privateKey);
  let token: { readonly value: string; readonly at: number } | undefined;
  const bearer = () => {
    const at = now();
    if (token === undefined || at - token.at >= TOKEN_REFRESH_MS) {
      token = { value: developerToken({ account, key, at }), at };
    }
    return token.value;
  };

  return {
    async dayAt({ place, day, timeZone }) {
      const url = new URL(
        `/api/v1/weather/en/${String(place.latitude)}/${String(place.longitude)}`,
        ORIGIN,
      );
      url.searchParams.set('dataSets', 'forecastDaily');
      url.searchParams.set('timezone', timeZone);
      const response = await fetchFn(url, {
        headers: { authorization: `Bearer ${bearer()}` },
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
      if (!response.ok) {
        throw new Error(`WeatherKit answered ${String(response.status)}`);
      }
      const days = DailyForecast.parse(await response.json()).forecastDaily?.days ?? [];
      const found = days.find((each) => dayOn(each.forecastStart, timeZone) === day);
      if (found === undefined) return undefined;
      const weather: DayWeather = {
        version: 1,
        ...(found.conditionCode === undefined ? {} : { condition: found.conditionCode }),
        high: found.temperatureMax,
        low: found.temperatureMin,
        ...(found.precipitationChance === undefined
          ? {}
          : { precipitationChance: found.precipitationChance }),
      };
      return weather;
    },
  };
}

/** The `YYYY-MM-DD` an instant falls on, on `timeZone`'s clock. */
function dayOn(instant: string, timeZone: string): string {
  // en-CA writes dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(instant));
}

/** The ES256 JWT WeatherKit's REST API takes. */
function developerToken({
  account,
  key,
  at,
}: {
  readonly account: WeatherKitAccount;
  readonly key: KeyObject;
  readonly at: number;
}): string {
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const iat = Math.floor(at / 1000);
  const unsigned = `${encode({
    alg: 'ES256',
    kid: account.keyId,
    id: `${account.teamId}.${account.serviceId}`,
  })}.${encode({ iss: account.teamId, iat, exp: iat + TOKEN_LIFETIME_S, sub: account.serviceId })}`;
  // JWS wants the raw r||s signature, not DER.
  const signature = sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' });
  return `${unsigned}.${signature.toString('base64url')}`;
}
