import { z } from 'zod';

import { ModelName, ModelPrice } from './usage.js';

// What model calls cost and how much a day may go on them, as kept in the database and changed by
// an admin, so a price or a cap changes without a deploy.

/** An admin's id, as the log keeps who changed the settings. */
export const MemberId = z.uuid().brand<'AiUsageMember'>();
export type MemberId = z.infer<typeof MemberId>;

const Cap = z.int().min(0).max(2_000_000_000);

const fields = {
  prices: z
    .record(ModelName, ModelPrice)
    .refine((prices) => Object.keys(prices).length <= 50, 'At most 50 models')
    .describe(
      'Each model’s prices, by provider/model. A call to a model without one is never made, so price a model before a setting names it. A change replaces the whole list.',
    ),
  squadDailyCapMicros: Cap.describe(
    'What one squad’s AI may spend a day, on the squad’s own clock: US dollars in millionths. Every call for the squad or one of its members counts (the coach, 请假条 drafts, the weekly awards). Once reached, the coach is off duty and 请假条 falls back to the dice until the next day; the weekly awards are counted but never held back.',
  ),
  dailyCapMicros: Cap.describe(
    'What every squad’s AI together may spend a day, New York’s day: US dollars in millionths. Once reached, the same holds for every squad until the next day.',
  ),
};

/** The settings, whole, as stored and logged. */
export const AiUsageSettings = z.strictObject({ version: z.literal(1), ...fields });
export type AiUsageSettings = z.infer<typeof AiUsageSettings>;

/** What an admin changes: any of the settings, the rest staying as they are. */
export const AiUsageSettingsChange = z.strictObject(fields).partial();
export type AiUsageSettingsChange = z.infer<typeof AiUsageSettingsChange>;
