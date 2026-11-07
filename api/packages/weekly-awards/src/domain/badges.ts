import { z } from 'zod';

// 头衔徽章: every weekly title comes with a badge, a shape in a colour with a glyph on it, which the
// model picks from a catalog kept in the award settings. Shapes are drawn by the app, so a new one
// needs the app first; colours carry their tone and glyphs are SF Symbol names, so a new one of
// either is a settings change. Every offered sport's icon is a glyph too, from the sports list.
// Replies carry each as plain text, and an app that doesn't know one draws its own default.

/** The shapes the app draws a badge in. */
export const BadgeShape = z.enum(['shield', 'hexagon', 'circle', 'scallop']);
export type BadgeShape = z.infer<typeof BadgeShape>;

/** A colour's id in the catalog, such as `track`. */
export const BadgeColour = z
  .string()
  .regex(/^[a-z][a-z0-9-]{0,31}$/u, 'Must be a lower-case id, such as track');
export type BadgeColour = z.infer<typeof BadgeColour>;

/** A colour's tone, as `#RRGGBB`. */
export const BadgeTone = z
  .string()
  .regex(/^#[0-9A-F]{6}$/, 'Must be #RRGGBB in capitals, such as #E65345')
  .meta({ description: 'The colour itself, as #RRGGBB: what the app paints the badge in.' });
export type BadgeTone = z.infer<typeof BadgeTone>;

/** An SF Symbol's name, such as `sun.max.fill`. */
export const BadgeGlyph = z
  .string()
  .regex(/^[a-z0-9]+(\.[a-z0-9]+)*$/u, 'Must be an SF Symbol name, such as sun.max.fill')
  .max(64);
export type BadgeGlyph = z.infer<typeof BadgeGlyph>;

/** A title's badge. */
export const Badge = z.strictObject({ shape: BadgeShape, colour: BadgeColour, glyph: BadgeGlyph });
export type Badge = z.infer<typeof Badge>;

/** The badge a title won before titles came with one. */
export const DEFAULT_BADGE: Badge = { shape: 'circle', colour: 'gym', glyph: 'star.fill' };

/** The tone of a colour the catalog no longer lists, or lists without one: the gym's steel. */
export const DEFAULT_TONE: BadgeTone = '#4A6C8C';

/** A badge as it is shown: with its colour's tone, from the catalog. */
export type ShownBadge = Badge & { readonly tone: BadgeTone };

const meaning = z
  .string()
  .min(1)
  .max(80)
  .meta({ description: 'What it stands for, for the model.' });

/** No id listed twice. */
const distinct = (list: readonly { readonly id: string }[]) =>
  new Set(list.map(({ id }) => id)).size === list.length;

/** What the model picks each badge from: the shapes, colours and glyphs on offer, with what each means. */
export const BadgeCatalog = z.strictObject({
  shapes: z
    .array(z.strictObject({ id: BadgeShape, meaning }))
    .min(1)
    .refine(distinct, 'Must not list a shape twice'),
  colours: z
    // A colour saved before colours had tones (as the API before them still reads it) has none,
    // and is shown in the gym's steel until one is set.
    .array(z.strictObject({ id: BadgeColour, tone: BadgeTone.optional(), meaning }))
    .min(1)
    .max(24)
    .refine(distinct, 'Must not list a colour twice'),
  glyphs: z
    .array(z.strictObject({ id: BadgeGlyph, meaning }))
    .min(1)
    .max(60)
    .refine(distinct, 'Must not list a glyph twice'),
});
export type BadgeCatalog = z.infer<typeof BadgeCatalog>;

/** A non-empty list, as `z.enum` takes it. */
const nonEmpty = (list: readonly string[]): [string, ...string[]] => {
  const [first, ...rest] = list;
  if (first === undefined) throw new Error('A badge catalog list is empty');
  return [first, ...rest];
};

/** The badge's shape in the model's reply: only what the catalog offers. */
export function badgeReplyFor(catalog: BadgeCatalog) {
  return z
    .strictObject({
      shape: z.enum(nonEmpty(catalog.shapes.map(({ id }) => id))),
      colour: z.enum(nonEmpty(catalog.colours.map(({ id }) => id))),
      glyph: z.enum(nonEmpty(catalog.glyphs.map(({ id }) => id))),
    })
    .meta({
      description:
        'The title’s badge (徽章): a shape, a colour and a glyph from `badges` in the prompt, ' +
        'picked to suit the title.',
    });
}

/** A sport's icon on offer as a glyph: its SF Symbol and what it means, from the sports list. */
export interface SportGlyph {
  readonly id: BadgeGlyph;
  readonly meaning: string;
}

/**
 * The catalog the model picks from: the settings' own, with every sport's icon among the glyphs
 * after them. A glyph the settings list already keeps their meaning.
 */
export function withSportGlyphs(
  catalog: BadgeCatalog,
  sports: readonly SportGlyph[],
): BadgeCatalog {
  const listed = new Set(catalog.glyphs.map(({ id }) => id));
  const added = sports.filter(({ id }) => {
    if (listed.has(id) || !BadgeGlyph.safeParse(id).success) return false;
    listed.add(id);
    return true;
  });
  return { ...catalog, glyphs: [...catalog.glyphs, ...added] };
}

/** `badge` with its colour's tone from `catalog`, or the gym's for a colour it no longer lists or lists without one. */
export function shownBadge(badge: Badge, catalog: BadgeCatalog): ShownBadge {
  const tone = catalog.colours.find(({ id }) => id === badge.colour)?.tone ?? DEFAULT_TONE;
  return { ...badge, tone };
}
