import { z } from 'zod';

// 头衔徽章: every weekly title comes with a badge, a shape in a colour with a glyph on it, which the
// model picks from a catalog kept in the award settings. Shapes and colours are drawn by the app,
// so a new one needs the app first; glyphs are SF Symbol names, so a new one is a settings change.
// Replies carry each as plain text, and an app that doesn't know one draws its own default.

/** The shapes the app draws a badge in. */
export const BadgeShape = z.enum(['shield', 'hexagon', 'circle', 'scallop']);
export type BadgeShape = z.infer<typeof BadgeShape>;

/** The colours a badge comes in: the scenes' own, by scene. */
export const BadgeColour = z.enum(['pool', 'track', 'gym', 'tennis', 'climbing']);
export type BadgeColour = z.infer<typeof BadgeColour>;

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
    .array(z.strictObject({ id: BadgeColour, meaning }))
    .min(1)
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
