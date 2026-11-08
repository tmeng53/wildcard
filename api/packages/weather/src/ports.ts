import type { DayWeather } from './domain/day-weather.js';
import type { MemberId, Place } from './domain/place.js';

/** Where each member roughly is: the latest place only, never a history. */
export interface PlaceStore {
  /** Keeps `place` as the member's place, replacing the one before. */
  save(input: {
    readonly member: MemberId;
    readonly place: Place;
    readonly at: Date;
  }): Promise<void>;
  /** Forgets the member's place. Safe to repeat. */
  remove(member: MemberId): Promise<void>;
  /** The places of those of `members` who have one. */
  placesOf(members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, Place>>;
}

/** The days' weather fetched already, one a place a day, kept a week. */
export interface WeatherDayStore {
  find(place: Place, day: string): Promise<DayWeather | undefined>;
  /** Keeps it for the place and day, replacing any kept; removes days a week older than `day`. */
  save(input: {
    readonly place: Place;
    readonly day: string;
    readonly weather: DayWeather;
  }): Promise<void>;
}

/** The weather provider: a place's day and the day before it, in one ask, on `timeZone`'s clock. */
export interface Forecasts {
  /** Leaves out a day the provider has nothing for; throws when it can't answer. */
  daysAt(input: {
    readonly place: Place;
    readonly day: string;
    readonly timeZone: string;
  }): Promise<{ readonly today?: DayWeather; readonly yesterday?: DayWeather }>;
}
