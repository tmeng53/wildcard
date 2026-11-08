import type { DayWeather } from '../domain/day-weather.js';
import { cellOf, type MemberId, type Place } from '../domain/place.js';
import type { Forecasts, PlaceStore, WeatherDayStore } from '../ports.js';

/** A member's weather: today's, and yesterday's when the provider has it. */
export interface MemberWeather {
  readonly today: DayWeather;
  readonly yesterday?: DayWeather;
}

export interface Weather {
  /** Keeps where the member roughly is, as its 0.1° cell, and answers that cell. */
  savePlace(member: MemberId, coordinates: Place): Promise<Place>;
  /** Forgets where the member is. Safe to repeat. */
  forgetPlace(member: MemberId): Promise<void>;
  /**
   * The weather on `day`, and on the day before, where each of these members is, for those with
   * a place. Each place's day is fetched once, whoever asks; a place the provider can't answer
   * for today is left out, and told to `failed`.
   */
  dayFor(input: {
    readonly members: readonly { readonly member: MemberId; readonly timeZone: string }[];
    readonly day: string;
  }): Promise<ReadonlyMap<MemberId, MemberWeather>>;
}

export function createWeather(deps: {
  readonly places: PlaceStore;
  readonly days: WeatherDayStore;
  /** Without it there is no weather, and every member's is left out. */
  readonly forecasts?: Forecasts;
  readonly clock: () => Date;
  readonly failed?: (error: unknown, place: Place) => void;
}): Weather {
  return {
    async savePlace(member, coordinates) {
      const place = cellOf(coordinates);
      await deps.places.save({ member, place, at: deps.clock() });
      return place;
    },

    forgetPlace: (member) => deps.places.remove(member),

    async dayFor({ members, day }) {
      const { forecasts } = deps;
      if (forecasts === undefined || members.length === 0) return new Map();
      const places = await deps.places.placesOf(members.map(({ member }) => member));
      const yesterday = dayBefore(day);
      // One look-up a place a day, however many members share it.
      const byPlace = new Map<string, Promise<DayWeather | undefined>>();
      const weatherAt = ({
        place,
        on,
        timeZone,
      }: {
        readonly place: Place;
        readonly on: string;
        readonly timeZone: string;
      }) => {
        const key = `${String(place.latitude)},${String(place.longitude)},${on}`;
        let found = byPlace.get(key);
        if (found === undefined) {
          found = fetchOnce({ place, day: on, timeZone });
          byPlace.set(key, found);
        }
        return found;
      };
      const fetchOnce = async (input: {
        readonly place: Place;
        readonly day: string;
        readonly timeZone: string;
      }) => {
        const kept = await deps.days.find(input.place, input.day);
        if (kept !== undefined) return kept;
        try {
          const fetched = await forecasts.dayAt(input);
          if (fetched !== undefined)
            await deps.days.save({ place: input.place, day: input.day, weather: fetched });
          return fetched;
        } catch (error) {
          deps.failed?.(error, input.place);
          return undefined;
        }
      };
      const answers = await Promise.all(
        members.map(async ({ member, timeZone }) => {
          const place = places.get(member);
          if (place === undefined) return undefined;
          const [today, before] = await Promise.all([
            weatherAt({ place, on: day, timeZone }),
            weatherAt({ place, on: yesterday, timeZone }),
          ]);
          if (today === undefined) return undefined;
          const weather: MemberWeather =
            before === undefined ? { today } : { today, yesterday: before };
          return [member, weather] as const;
        }),
      );
      return new Map(answers.filter((each) => each !== undefined));
    },
  };
}

/** The `YYYY-MM-DD` before `day`. */
function dayBefore(day: string): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
}
