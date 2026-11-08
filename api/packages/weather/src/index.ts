// @wildcard/weather: roughly where each member is (a 0.1° cell, the latest only) and the day's
// weather there, which the coach reads. Squadmates and the model never see the place.

export {
  createPostgresPlaceStore,
  createPostgresWeatherDayStore,
  type WeatherTables,
} from './adapters/postgres-weather-stores.js';
export {
  createWeatherKitForecasts,
  type WeatherKitAccount,
} from './adapters/weatherkit-forecasts.js';
export { DayWeather, weatherWords } from './domain/day-weather.js';
export { cellOf, Coordinates, MemberId, type Place } from './domain/place.js';
export type { Forecasts, PlaceStore, WeatherDayStore } from './ports.js';
export { createWeather, type Weather } from './use-cases/weather.js';
