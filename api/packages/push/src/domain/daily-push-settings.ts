import { z } from 'zod';

// The daily progress push for everyone, kept in the database so it changes without a deploy:
// whether it goes out at all (a switch for when it misbehaves), and the hour on each member's
// own clock it goes out at; and the Sunday 去安排下周 push beside it, its switch and the time on
// each member's own clock it goes out at that evening. Each member's own switch (PushTopic
// `dailyProgress`) applies to both.

export const DailyPushSettings = z.strictObject({
  version: z.literal(2),
  /** Off, nobody gets the daily push; members' own switches are kept as they are. */
  sending: z.boolean(),
  /** The hour on each member's own clock it goes out at, or later that evening: 0 to 23. */
  hour: z.int().min(0).max(23),
  /** Off, nobody gets the Sunday 去安排下周 push. */
  planReminderSending: z.boolean(),
  /** The hour on each member's own clock on Sunday it goes out at, or later that day: 0 to 23. */
  planReminderHour: z.int().min(0).max(23),
  /** The minute past that hour: 0 to 59. */
  planReminderMinute: z.int().min(0).max(59),
});
export type DailyPushSettings = z.infer<typeof DailyPushSettings>;

/** What an admin changes: any of them, the rest as they are. */
export const DailyPushSettingsChange = DailyPushSettings.omit({ version: true }).partial();
export type DailyPushSettingsChange = z.infer<typeof DailyPushSettingsChange>;
