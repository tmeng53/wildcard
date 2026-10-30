import { z } from 'zod';

// @wildcard/sport-ids: how a sport is named on the wire and in stored check-ins and plans. The
// sports module keeps the list itself; check-ins only need the shape of an id and ask the list
// whether one is in it.

/** `custom` stands for 其他, a sport the member names themselves; no listed sport has it. */
export const CUSTOM_SPORT = 'custom';

/** The shape of a sport's id, such as `run` or `trailRun`: camelCase letters and digits. */
export const SPORT_ID_PATTERN = /^[a-z][A-Za-z0-9]{0,39}$/;

/** A listed sport's id. Never changes. */
export const SportId = z
  .string()
  .regex(SPORT_ID_PATTERN)
  .refine((id) => id !== CUSTOM_SPORT, { message: '`custom` is not a listed sport' });
export type SportId = z.infer<typeof SportId>;
