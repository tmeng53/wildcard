import { z } from 'zod';

// The teammate push for everyone (a squadmate's 训练, told as it is posted), kept in the database
// so it changes without a deploy: whether it goes out at all, and how many may ring on one
// member's phone in 24 hours. Each member's own switch (PushTopic `dailyProgress`) still applies.

export const TeammatePushSettings = z.strictObject({
  version: z.literal(1),
  /** Off, nobody gets teammate pushes; members' own switches are kept as they are. */
  sending: z.boolean(),
  /**
   * The most teammate pushes that ring on one member's phone in any 24 hours: 0 to 50. The ones
   * past it still arrive, silently.
   */
  dailyRings: z.int().min(0).max(50),
});
export type TeammatePushSettings = z.infer<typeof TeammatePushSettings>;

/** What an admin changes: any of them, the rest as they are. */
export const TeammatePushSettingsChange = TeammatePushSettings.omit({ version: true }).partial();
export type TeammatePushSettingsChange = z.infer<typeof TeammatePushSettingsChange>;
