import { z } from 'zod';

import { Hex, SceneId } from './catalog.js';

const Name = z.string().trim().min(1).max(40);

export const LocalizedNamesInput = z.strictObject({ zhHans: Name, en: Name, zhHant: Name });

export const SceneColorsInput = z.strictObject({
  signature: Hex.meta({ description: 'The 打卡 button, the week’s icons, the poster.' }),
  onSignature: Hex.meta({ description: 'Text drawn on the signature.' }),
  wash: Hex.meta({ description: 'Its light ground.' }),
  text: Hex.meta({ description: 'Its text colour on light grounds.' }),
  floor: Hex,
});

/** Adds a scene, or replaces every field of one. */
export const SceneEdit = z
  .strictObject({
    id: SceneId.meta({ description: 'Its id, camelCase, such as `ski`. Never changes.' }),
    names: LocalizedNamesInput,
    colors: SceneColorsInput,
    offered: z.boolean().meta({ description: 'False retires it: the picker stops offering it.' }),
    switchId: SceneId.optional().meta({
      description:
        'The switch a limited scene follows (get_switches), such as `winter`: squads may pick it ' +
        'only while it is on. Leave it out for a scene open all year.',
    }),
    takeover: z
      .boolean()
      .optional()
      .meta({
        description:
          'True for a takeover scene (needs a switchId): while its switch is on, every squad’s ' +
          'home shows it in place of the squad’s pick (which is back when the switch goes off), and ' +
          'the picker never offers it. Leave it out for a scene squads pick.',
      }),
    position: z.int().min(1).optional().meta({
      description:
        'Its place in the picker, from 1. Leave it out to keep its place, or put a new one last.',
    }),
  })
  .refine(({ takeover, switchId }) => takeover !== true || switchId !== undefined, {
    message: 'a takeover scene follows a switch',
    path: ['switchId'],
  });
export type SceneEdit = z.infer<typeof SceneEdit>;
