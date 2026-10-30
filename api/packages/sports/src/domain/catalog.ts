import type { SportId } from '@wildcard/sport-ids';

// The sports list every picker in the app shows, as the database keeps it
// (supabase/migrations, `sport_categories`, `sports` and `sport_picks`): data, so a new sport,
// name, icon or order needs no app release.

/** A name in each of the app's languages. */
export interface LocalizedNames {
  readonly zhHans: string;
  readonly en: string;
  readonly zhHant: string;
}

export interface ListedSport {
  readonly id: SportId;
  readonly names: LocalizedNames;
  /** The name on a card or poster row, for a sport whose name is too long there. */
  readonly shortNames?: LocalizedNames;
  /** An SF Symbol name. */
  readonly icon: string;
  /** False for a sport the pickers no longer offer; check-ins that name it still show it. */
  readonly offered: boolean;
}

/** One of the picker's tabs, with its sports in order. */
export interface SportCategory {
  readonly id: string;
  readonly names: LocalizedNames;
  readonly sports: readonly ListedSport[];
}

/** The short lists some screens show before the whole list. */
export const PICK_LISTS = ['signUpCommon', 'checkInQuick'] as const;
export type PickList = (typeof PICK_LISTS)[number];

export interface SportCatalog {
  /** In the picker's order. */
  readonly categories: readonly SportCategory[];
  /** Each short list's sports, in order. */
  readonly picks: Readonly<Record<PickList, readonly SportId[]>>;
}
