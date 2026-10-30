import {
  CategoryEdit,
  PicksEdit,
  SportEdit,
  type Sports,
  type SportsAdmin,
} from '@wildcard/sports';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The sports list every picker shows: its tabs, each sport's names, icon and place, and the
// short lists. A change reaches apps through the public catalog within a minute, with no app
// release. Sports are retired, never deleted, and keep their ids, since check-ins name them.

interface SportToolDependencies {
  readonly sports: Sports & SportsAdmin;
}

/** `get_sports`: the whole list now. */
export function getSports({ sports }: SportToolDependencies) {
  return adminTool({
    name: 'get_sports',
    title: 'Read the sports list',
    description:
      'Shows the sports list every picker shows: its tabs (categories) in order, each with its ' +
      'sports in order (id, names in zh-Hans, en and zh-Hant, shortNames when a name is too ' +
      'long for a card, SF Symbol icon, offered), and the short lists signUpCommon and ' +
      'checkInQuick. Retired sports (offered false) are listed too.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({ version: 1, ...(await sports.catalog()) }),
  });
}

/** `put_sport`: adds a sport, or replaces one whole. */
export function putSport({ sports }: SportToolDependencies) {
  return adminTool({
    name: 'put_sport',
    title: 'Add or change a sport',
    description:
      'Adds a sport, or replaces every field of a listed one (read it with get_sports first: ' +
      'a field left out is not kept, and leaving out shortNames removes them). Moves it to ' +
      'another tab or place when asked. To retire a sport set offered to false: pickers stop ' +
      'offering it and check-ins that name it keep showing it; take it off the short lists ' +
      'first. Ids never change and sports are never deleted. Apps see it within a minute. ' +
      'Returns the list now.',
    changes: true,
    input: SportEdit,
    run: async (edit) => ({ version: 1, ...(await sports.putSport(edit)) }),
  });
}

/** `put_sport_category`: adds a picker tab, or renames or moves one. */
export function putSportCategory({ sports }: SportToolDependencies) {
  return adminTool({
    name: 'put_sport_category',
    title: 'Add or change a sports tab',
    description:
      'Adds a tab (category) to the sports picker, or renames or moves one. A new tab shows ' +
      'once a sport is put in it. Apps see it within a minute. Returns the list now.',
    changes: true,
    input: CategoryEdit,
    run: async (edit) => ({ version: 1, ...(await sports.putCategory(edit)) }),
  });
}

/** `set_sport_picks`: replaces a short list. */
export function setSportPicks({ sports }: SportToolDependencies) {
  return adminTool({
    name: 'set_sport_picks',
    title: 'Set a short list of sports',
    description:
      'Replaces one short list, whole and in order: signUpCommon (sign-up’s most common ' +
      'sports) or checkInQuick (练了’s quick picks). Each must be a sport the pickers offer. ' +
      'Apps see it within a minute. Returns the list now.',
    changes: true,
    input: PicksEdit,
    run: async (edit) => ({ version: 1, ...(await sports.setPicks(edit)) }),
  });
}

export const sportTools = (deps: SportToolDependencies) => [
  getSports(deps),
  putSport(deps),
  putSportCategory(deps),
  setSportPicks(deps),
];
