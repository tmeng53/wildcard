import { z } from 'zod';

/**
 * One day's weather at a place, as stored and as the coach reads it: the day's condition, its
 * high and low in °C, and the chance of rain or snow. The condition is WeatherKit's code (such as
 * `Rain`); a code this build doesn't know is kept and left out of the words.
 */
export const DayWeather = z.strictObject({
  version: z.literal(1),
  condition: z.string().min(1).max(64).optional(),
  high: z.number().min(-100).max(100),
  low: z.number().min(-100).max(100),
  /** 0 to 1. */
  precipitationChance: z.number().min(0).max(1).optional(),
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

/** `小雨，8–13°C，降水概率 80%`: the day's weather as the coach's task says it. */
export function weatherWords(weather: DayWeather): string {
  const words = weather.condition === undefined ? undefined : CONDITION_WORDS[weather.condition];
  const temperatures = `${String(Math.round(weather.low))}–${String(Math.round(weather.high))}°C`;
  // A small chance says nothing the condition doesn't.
  const chance =
    weather.precipitationChance === undefined || weather.precipitationChance < 0.2
      ? undefined
      : `降水概率 ${String(Math.round(weather.precipitationChance * 100))}%`;
  return [words, temperatures, chance].filter((each) => each !== undefined).join('，');
}
