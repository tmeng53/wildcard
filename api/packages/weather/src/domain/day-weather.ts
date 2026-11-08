import { z } from 'zod';

/** Part of a day (7am to 7pm, or the night after) as WeatherKit forecasts it. */
const DayPart = z.strictObject({
  condition: z.string().min(1).max(64).optional(),
  /** Average, km/h. */
  windSpeed: z.number().min(0).max(500).optional(),
  /** Where the wind comes from, in degrees. */
  windDirection: z.number().min(0).max(360).optional(),
  /** 0 to 1. */
  humidity: z.number().min(0).max(1).optional(),
});

/**
 * One day's weather at a place, as stored and as the coach reads it: everything WeatherKit's daily
 * forecast says that bears on training outdoors (Tracy, 2026-11-08: all of it). The condition is
 * WeatherKit's code (such as `Rain`); a code this build doesn't know is kept and left out of the
 * words. Every field but the high and low may be missing, as an older row's are.
 */
export const DayWeather = z.strictObject({
  version: z.literal(1),
  condition: z.string().min(1).max(64).optional(),
  high: z.number().min(-100).max(100),
  low: z.number().min(-100).max(100),
  /** 0 to 1. */
  precipitationChance: z.number().min(0).max(1).optional(),
  /** Rain, sleet and melted snow together, mm. */
  precipitationAmount: z.number().min(0).max(2000).optional(),
  /** Snow depth, mm. */
  snowfallAmount: z.number().min(0).max(5000).optional(),
  maxUvIndex: z.number().int().min(0).max(20).optional(),
  sunrise: z.iso.datetime().optional(),
  sunset: z.iso.datetime().optional(),
  daytime: DayPart.optional(),
  overnight: DayPart.optional(),
});
export type DayWeather = z.infer<typeof DayWeather>;

/** Each condition WeatherKit names, in the words the coach reads. */
const CONDITION_WORDS: Readonly<Record<string, string>> = {
  Clear: '晴',
  MostlyClear: '晴',
  PartlyCloudy: '多云',
  MostlyCloudy: '多云',
  Cloudy: '阴',
  Foggy: '有雾',
  Haze: '有霾',
  Smoke: '有烟',
  Dust: '有沙尘',
  BlowingDust: '有沙尘',
  Breezy: '有风',
  Windy: '大风',
  Drizzle: '毛毛雨',
  Rain: '雨',
  HeavyRain: '大雨',
  Showers: '阵雨',
  ScatteredShowers: '阵雨',
  SunShowers: '太阳雨',
  IsolatedThunderstorms: '雷阵雨',
  ScatteredThunderstorms: '雷阵雨',
  Thunderstorms: '雷雨',
  StrongStorms: '强雷雨',
  SevereThunderstorm: '强雷雨',
  Flurries: '小雪',
  Snow: '雪',
  SnowShowers: '阵雪',
  ScatteredSnowShowers: '阵雪',
  HeavySnow: '大雪',
  Blizzard: '暴风雪',
  BlowingSnow: '风吹雪',
  Sleet: '雨夹雪',
  WintryMix: '雨夹雪',
  MixedRainAndSleet: '雨夹雪',
  MixedRainAndSnow: '雨夹雪',
  MixedRainfall: '雨',
  MixedSnowAndSleet: '雨夹雪',
  FreezingDrizzle: '冻毛毛雨',
  FreezingRain: '冻雨',
  Hail: '冰雹',
  Frigid: '极冷',
  Hot: '炎热',
  Hurricane: '飓风',
  TropicalStorm: '热带风暴',
  Tornado: '龙卷风',
};

/** Where the wind comes from, by eighths of the compass. */
const WIND_FROM = ['北风', '东北风', '东风', '东南风', '南风', '西南风', '西风', '西北风'];

const one = (value: number) => String(Math.round(value * 10) / 10);

/** `7:05`, an instant on `timeZone`'s clock. */
function clockOn(instant: string, timeZone: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(instant));
}

/** How much fell or will fall: rain in mm, snow in cm, only when it is more than a trace. */
function amounts(weather: DayWeather): string[] {
  const snow = weather.snowfallAmount ?? 0;
  const wet = weather.precipitationAmount ?? 0;
  return [
    ...(snow >= 1 ? [`降雪 ${one(snow / 10)} 厘米`] : []),
    ...(wet >= 0.5 && snow < 1 ? [`降水 ${one(wet)} 毫米`] : []),
  ];
}

/** The day's wind, humidity and night, from its parts. */
function parts(weather: DayWeather): string[] {
  const { daytime, overnight } = weather;
  const wind =
    daytime?.windSpeed === undefined
      ? []
      : [
          `白天${
            daytime.windDirection === undefined
              ? '风'
              : (WIND_FROM[Math.round(daytime.windDirection / 45) % 8] ?? '风')
          } ${String(Math.round(daytime.windSpeed))} 公里/小时`,
        ];
  const humidity =
    daytime?.humidity === undefined ? [] : [`湿度 ${String(Math.round(daytime.humidity * 100))}%`];
  const night =
    overnight?.condition === undefined ? undefined : CONDITION_WORDS[overnight.condition];
  return [...wind, ...humidity, ...(night === undefined ? [] : [`夜里${night}`])];
}

/**
 * `今天雨，8–13°C，降水概率 80%，…；昨天大雪，降雪 25 厘米`: the weather as the coach's task says
 * it, times on the member's clock. Yesterday says only what it was and what fell.
 */
export function weatherWords(
  weather: DayWeather,
  {
    yesterday,
    timeZone = 'UTC',
  }: { readonly yesterday?: DayWeather; readonly timeZone?: string } = {},
): string {
  const today = [
    ...base(weather),
    ...amounts(weather),
    ...parts(weather),
    ...(weather.maxUvIndex !== undefined && weather.maxUvIndex >= 3
      ? [`紫外线 ${String(weather.maxUvIndex)}`]
      : []),
    ...(weather.sunrise === undefined ? [] : [`日出 ${clockOn(weather.sunrise, timeZone)}`]),
    ...(weather.sunset === undefined ? [] : [`日落 ${clockOn(weather.sunset, timeZone)}`]),
  ];
  const before = yesterday === undefined ? [] : [...base(yesterday), ...amounts(yesterday)];
  return [
    `今天${today.join('，')}`,
    ...(before.length === 0 ? [] : [`昨天${before.join('，')}`]),
  ].join('；');
}

/** The condition, the low and high, and a real chance of rain or snow. */
function base(weather: DayWeather): string[] {
  const words = weather.condition === undefined ? undefined : CONDITION_WORDS[weather.condition];
  const temperatures = `${String(Math.round(weather.low))}–${String(Math.round(weather.high))}°C`;
  // A small chance says nothing the condition doesn't.
  const chance =
    weather.precipitationChance === undefined || weather.precipitationChance < 0.2
      ? undefined
      : `降水概率 ${String(Math.round(weather.precipitationChance * 100))}%`;
  return [words, temperatures, chance].filter((each) => each !== undefined);
}
