import {
  CoachEdit,
  CoachSettingsChange,
  MemberId,
  type CoachCatalogAdmin,
  type CoachSettingsAdmin,
} from '@wildcard/coach';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The AI coach: the settings every coach runs with, and the coaches themselves (identity and
// soul). A change applies to the next wake, with no deploy, and each one is logged with the
// whole new value, so an edit is undone by saving the old value.

interface CoachToolDependencies {
  readonly settings: CoachSettingsAdmin;
  readonly coaches: CoachCatalogAdmin;
}

/** `get_coach_settings`: what every coach runs with now. */
export function getCoachSettings({ settings }: CoachToolDependencies) {
  return adminTool({
    name: 'get_coach_settings',
    title: 'Read the coach settings',
    description:
      'Shows what every AI coach runs with now: whether coaching is on (and, for a trial, only ' +
      'for which squads), the model (openai/…), the rules every coach follows (Chinese; each ' +
      'coach’s soul comes after them), and the model’s prices per million input and output ' +
      'tokens in millionths of a US dollar, which each wake’s cost is counted at.',
    changes: false,
    input: z.strictObject({}),
    run: async () => settings.current(),
  });
}

/** `change_coach_settings`: changes some of them. */
export function changeCoachSettings({ settings }: CoachToolDependencies) {
  return adminTool({
    name: 'change_coach_settings',
    title: 'Change the coach settings',
    description:
      'Changes any of the coach settings; the rest stay as they are. Applies to the next wake. ' +
      'Turning coaching on with onlySquads set wakes coaches only for those squads (a trial); ' +
      'onlySquads null means every squad. When the model changes, set its prices too. Returns ' +
      'the settings now.',
    changes: true,
    input: CoachSettingsChange.refine((input) => Object.keys(input).length > 0, {
      message: 'Name at least one setting to change',
    }),
    run: async (change, { admin }) => settings.change(change, MemberId.parse(admin)),
  });
}

/** `list_coaches`: every coach, retired ones too. */
export function listCoaches({ coaches }: CoachToolDependencies) {
  return adminTool({
    name: 'list_coaches',
    title: 'List the coaches',
    description:
      'Lists every AI coach, retired ones (offered false) too: id, tier (entry 入门, advanced ' +
      '进阶, pro 专业), name, catchphrase, credentials (the fictional 资历卡), style, soul (the ' +
      'persona prompt only the model reads), look (the character’s art id) and offered.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({ version: 1, coaches: await coaches.list() }),
  });
}

/** `put_coach`: adds a coach, or replaces one whole. */
export function putCoach({ coaches }: CoachToolDependencies) {
  return adminTool({
    name: 'put_coach',
    title: 'Add or change a coach',
    description:
      'Adds an AI coach, or replaces every field of one (read it with list_coaches first: a ' +
      'field left out is refused, not kept). Every squad gets the same coach: its identity and ' +
      'soul never change per squad. To retire a coach set offered to false. Ids never change ' +
      'and coaches are never deleted. Applies to the next wake. Returns the coach now.',
    changes: true,
    input: CoachEdit,
    run: async (edit, { admin }) => coaches.put(edit, MemberId.parse(admin)),
  });
}

export const coachTools = (deps: CoachToolDependencies) => [
  getCoachSettings(deps),
  changeCoachSettings(deps),
  listCoaches(deps),
  putCoach(deps),
];
