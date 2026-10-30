import { SportId } from '@wildcard/sport-ids';
import { z } from 'zod';

import { PICK_LISTS } from './catalog.js';

// What an admin may change in the sports list, in the shapes the database keeps
// (supabase/migrations, `sport_categories`, `sports` and `sport_picks`). A sport is never
// deleted and keeps its id; `offered: false` retires it.

const Name = z.string().trim().min(1).max(40);

export const LocalizedNamesInput = z.strictObject({ zhHans: Name, en: Name, zhHant: Name });

/** A category's id: camelCase letters and digits, like a sport's. */
export const CategoryId = z.string().regex(/^[a-z][A-Za-z0-9]{0,39}$/);
export type CategoryId = z.infer<typeof CategoryId>;

/** An SF Symbol name, such as `figure.run`. */
export const SportIcon = z.string().regex(/^[a-z0-9]+(\.[a-z0-9]+)*$/);

/** A place in a list, counted from 1; one past the end, or more, puts it last. */
const Position = z.int().min(1);

/** A sport as a whole: a new one, or every field of one already listed. */
export const SportEdit = z.strictObject({
  id: SportId.describe('Its id, camelCase, such as `pickleball`. Never changes.'),
  category: CategoryId.describe('The id of the picker tab it is listed under.'),
  names: LocalizedNamesInput,
  shortNames: LocalizedNamesInput.optional().describe(
    'A shorter name for cards and poster rows, for a name too long there; leave it out for none.',
  ),
  icon: SportIcon.describe('An SF Symbol name, such as `figure.run`.'),
  offered: z
    .boolean()
    .describe('False retires it: pickers stop offering it, old check-ins keep it.'),
  position: Position.optional().describe(
    'Its place in its tab, from 1. Leave it out to keep its place, or put a new one last.',
  ),
});
export type SportEdit = z.infer<typeof SportEdit>;

/** A picker tab as a whole. */
export const CategoryEdit = z.strictObject({
  id: CategoryId.describe('Its id, camelCase, such as `racket`.'),
  names: LocalizedNamesInput,
  position: Position.optional().describe(
    'Its place among the tabs, from 1. Leave it out to keep its place, or put a new one last.',
  ),
});
export type CategoryEdit = z.infer<typeof CategoryEdit>;

/** One short list, whole and in order. */
export const PicksEdit = z.strictObject({
  list: z.enum(PICK_LISTS),
  sports: z
    .array(SportId)
    .min(1)
    .max(12)
    .refine((ids) => new Set(ids).size === ids.length, { message: 'A sport is listed twice' }),
});
export type PicksEdit = z.infer<typeof PicksEdit>;
