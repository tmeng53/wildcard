import { z } from 'zod';

// @wildcard/sport-ids: how a sport is named on the wire and in stored check-ins and plans. The
// sports module keeps the list itself; check-ins only need the shape of an id and ask the list
// whether one is in it.

/** `custom` stands for 其他, a sport the member names themselves; no listed sport has it. */
export const CUSTOM_SPORT = 'custom';

/** A listed sport's id, such as `run` or `trailRun`: camelCase letters and digits. Never changes. */
export const SportId = z
  .string()
  .regex(/^[a-z][A-Za-z0-9]{0,39}$/)
  .refine((id) => id !== CUSTOM_SPORT, { message: '`custom` is not a listed sport' });
export type SportId = z.infer<typeof SportId>;
