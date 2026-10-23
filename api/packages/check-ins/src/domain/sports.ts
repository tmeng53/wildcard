import { CUSTOM_SPORT, SportId } from '@wildcard/sport-ids';
import { z } from 'zod';

/**
 * A 练了's `sport`: a listed sport's id, or `custom` with the member's own name in
 * `customSport`. The list itself is data the sports module keeps (`GET /public/catalog`), so the
 * shape is all the contract says; saving asks the list whether the id is in it.
 */
export const SportKey = z.union([SportId, z.literal(CUSTOM_SPORT)]).meta({
  id: 'Sport',
  description:
    'A listed sport’s id from `GET /public/catalog`, or `custom` with the member’s own name in ' +
    '`customSport`.',
});
export type SportKey = z.infer<typeof SportKey>;
