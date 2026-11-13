import type { DayWeather } from '../domain/day-weather.js';
import { cellOf, type MemberId, type MemberPlace, type Place } from '../domain/place.js';
import type { Forecasts, PlaceStore, WeatherDayStore } from '../ports.js';

/** A member's weather: today's, yesterday's when the provider has it, and the city it is in. */
export interface MemberWeather {
  readonly today: DayWeather;
  readonly yesterday?: DayWeather;
  /** The city the member's phone named, when it could. */
  readonly city?: string;
}

export interface Weather {
  /**
   * Keeps where the member roughly is, as its 0.1° cell, with the city their phone named there,
   * and answers what it kept.
   */
  savePlace(
    member: MemberId,
    where: Place & { readonly city?: string | undefined },
  ): Promise<MemberPlace>;
  /** Forgets where the member is. Safe to repeat. */
  forgetPlace(member: MemberId): Promise<void>;
  /**
   * The weather on `day`, and on the day before, where each of these members is, for those with
   * a place. Each place is asked for once a day, both days in one ask, whoever asks; a place the
   * provider can't answer for today is left out, and an error is told to `failed`.
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
    async savePlace(member, { city, ...coordinates }) {
      const place = cellOf(coordinates);
      await deps.places.save({
        member,
        place,
        ...(city === undefined ? {} : { city }),
        at: deps.clock(),
      });
      return city === undefined ? { place } : { place, city };
    },

    forgetPlace: (member) => deps.places.remove(member),

    async dayFor({ members, day }) {
      const { forecasts } = deps;
      if (forecasts === undefined || members.length === 0) return new Map();
      const places = await deps.places.placesOf(members.map(({ member }) => member));
      const yesterday = dayBefore(day);
      // One look-up a place a day, however many members share it, and one ask holds both days.
      const byPlace = new Map<string, Promise<Partial<MemberWeather>>>();
      const weatherAt = (place: Place, timeZone: string) => {
        const key = `${String(place.latitude)},${String(place.longitude)}`;
        let found = byPlace.get(key);
        if (found === undefined) {
          found = fetchOnce({ place, timeZone });
          byPlace.set(key, found);
        }
        return found;
      };
      const fetchOnce = async ({
        place,
        timeZone,
      }: {
        readonly place: Place;
        readonly timeZone: string;
      }): Promise<Partial<MemberWeather>> => {
        const [kept, keptBefore] = await Promise.all([
          deps.days.find(place, day),
          deps.days.find(place, yesterday),
        ]);
        if (kept !== undefined)
          return keptBefore === undefined
            ? { today: kept }
            : { today: kept, yesterday: keptBefore };
        try {
          const fetched = await forecasts.daysAt({ place, day, timeZone });
          if (fetched.today !== undefined)
            await deps.days.save({ place, day, weather: fetched.today });
          if (fetched.yesterday !== undefined)
            await deps.days.save({ place, day: yesterday, weather: fetched.yesterday });
          const before = fetched.yesterday ?? keptBefore;
          return {
            ...(fetched.today === undefined ? {} : { today: fetched.today }),
            ...(before === undefined ? {} : { yesterday: before }),
          };
        } catch (error) {
          deps.failed?.(error, place);
          return keptBefore === undefined ? {} : { yesterday: keptBefore };
        }
      };
      const answers = await Promise.all(
        members.map(async ({ member, timeZone }) => {
          const kept = places.get(member);
          if (kept === undefined) return undefined;
          const { today, yesterday: before } = await weatherAt(kept.place, timeZone);
          if (today === undefined) return undefined;
          const weather: MemberWeather = {
            today,
            ...(before === undefined ? {} : { yesterday: before }),
            ...(kept.city === undefined ? {} : { city: kept.city }),
          };
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
