import { z } from 'zod';

import { Hex, MonthDay, SceneId } from './catalog.js';

const Name = z.string().trim().min(1).max(40);

export const LocalizedNamesInput = z.strictObject({ zhHans: Name, en: Name, zhHant: Name });

export const SceneColorsInput = z.strictObject({
  signature: Hex.meta({ description: 'The 打卡 button, the week’s icons, the poster.' }),
  onSignature: Hex.meta({ description: 'Text drawn on the signature.' }),
  wash: Hex.meta({ description: 'Its light ground.' }),
  text: Hex.meta({ description: 'Its text colour on light grounds.' }),
  floor: Hex,
});

export const SceneWindowInput = z
  .strictObject({
    start: MonthDay.meta({ description: 'First open day, `MM-DD`, New York time.' }),
    end: MonthDay.meta({
      description: 'Last open day, `MM-DD`; may be before start (over New Year).',
    }),
  })
  .meta({ description: 'The days of every year the scene is open, both included.' });

/** Adds a scene, or replaces every field of one. */
export const SceneEdit = z.strictObject({
  id: SceneId.meta({ description: 'Its id, camelCase, such as `ski`. Never changes.' }),
  names: LocalizedNamesInput,
  colors: SceneColorsInput,
  offered: z.boolean().meta({ description: 'False retires it: the picker stops offering it.' }),
  window: SceneWindowInput.optional().meta({
    description: 'Leave it out for a scene open all year.',
  }),
  position: z.int().min(1).optional().meta({
    description:
      'Its place in the picker, from 1. Leave it out to keep its place, or put a new one last.',
  }),
});
export type SceneEdit = z.infer<typeof SceneEdit>;

/** Changes only a scene's open window. */
export const SceneWindowEdit = z.strictObject({
  id: SceneId,
  window: SceneWindowInput.nullable().meta({ description: 'Null opens it all year.' }),
});
export type SceneWindowEdit = z.infer<typeof SceneWindowEdit>;
