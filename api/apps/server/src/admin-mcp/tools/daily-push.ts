import { DailyPushSettingsChange, MemberId, type DailyPushSettingsAdmin } from '@wildcard/push';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The daily progress push for everyone: whether it goes out at all, and the hour on each
// member's own clock; and the same for the Sunday 去安排下周 push. A change applies to the next
// run, with no deploy, and each one is logged with the whole new value.

interface DailyPushToolDependencies {
  readonly settings: DailyPushSettingsAdmin;
}

/** `get_daily_push_settings`: whether the daily and Sunday pushes go out, and when. */
export function getDailyPushSettings({ settings }: DailyPushToolDependencies) {
  return adminTool({
    name: 'get_daily_push_settings',
    title: 'Read the daily push settings',
    description:
      'Shows whether the daily progress push goes out at all (`sending`) and the hour on each ' +
      'member’s own clock it goes out at (`hour`, 0 to 23), and the same for the Sunday ' +
      '去安排下周 push (`planReminderSending`, at `planReminderHour`:`planReminderMinute` on Sunday ' +
      'on each member’s own clock). Members’ own daily push switches apply to both.',
    changes: false,
    input: z.strictObject({}),
    run: async () => settings.current(),
  });
}

/** `change_daily_push_settings`: turns either push off or on, or moves its time. */
export function changeDailyPushSettings({ settings }: DailyPushToolDependencies) {
  return adminTool({
    name: 'change_daily_push_settings',
    title: 'Change the daily push settings',
    description:
      'Changes any of the daily push settings; the rest stay as they are. `sending: false` stops ' +
      'the daily push for everyone from the next run, keeping each member’s own switch; `hour` ' +
      'moves it on every member’s own clock. `planReminderSending`, `planReminderHour` and ' +
      '`planReminderMinute` do the same for the Sunday 去安排下周 push. Returns the settings now.',
    changes: true,
    input: DailyPushSettingsChange.refine((change) => Object.keys(change).length > 0, {
      message: 'Name at least one setting to change',
    }),
    run: async (change, { admin }) => settings.change(change, MemberId.parse(admin)),
  });
}

export const dailyPushTools = (deps: DailyPushToolDependencies) => [
  getDailyPushSettings(deps),
  changeDailyPushSettings(deps),
];
