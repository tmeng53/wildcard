import {
  MemberId,
  TeammatePushSettingsChange,
  type TeammatePushSettingsAdmin,
} from '@wildcard/push';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The teammate push for everyone (a squadmate's 训练, told to the squad as it is posted): whether
// it goes out at all, and how many may ring on one member's phone in 24 hours. A change applies
// to the next post, with no deploy, and each one is logged with the whole new value.

interface TeammatePushToolDependencies {
  readonly settings: TeammatePushSettingsAdmin;
}

/** `get_teammate_push_settings`: whether teammate pushes go out, and how many ring. */
export function getTeammatePushSettings({ settings }: TeammatePushToolDependencies) {
  return adminTool({
    name: 'get_teammate_push_settings',
    title: 'Read the teammate push settings',
    description:
      'Shows whether a squadmate’s 训练 is pushed to the rest of the squad as it is posted ' +
      '(`sending`) and how many of those pushes may ring on one member’s phone in any 24 hours ' +
      '(`dailyRings`, 0 to 50); the ones past it arrive silently. Each member’s own switch for ' +
      'it (队友练完提醒) applies on top.',
    changes: false,
    input: z.strictObject({}),
    run: async () => settings.current(),
  });
}

/** `change_teammate_push_settings`: turns them off or on, or changes how many ring. */
export function changeTeammatePushSettings({ settings }: TeammatePushToolDependencies) {
  return adminTool({
    name: 'change_teammate_push_settings',
    title: 'Change the teammate push settings',
    description:
      'Changes either teammate push setting; the other stays as it is. `sending: false` stops ' +
      'teammate pushes for everyone from the next post, keeping each member’s own switch; ' +
      '`dailyRings` is how many may ring on one member’s phone in any 24 hours (0 makes them ' +
      'all silent). Returns the settings now.',
    changes: true,
    input: TeammatePushSettingsChange.refine((change) => Object.keys(change).length > 0, {
      message: 'Name at least one setting to change',
    }),
    run: async (change, { admin }) => settings.change(change, MemberId.parse(admin)),
  });
}

export const teammatePushTools = (deps: TeammatePushToolDependencies) => [
  getTeammatePushSettings(deps),
  changeTeammatePushSettings(deps),
];
