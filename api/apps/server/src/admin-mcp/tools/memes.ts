import { MemeDraft, MemePhrase, type Memes } from '@wildcard/memes';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The meme library's tools: what the AI writing a 今日免责声明 may draw on. Memes are turned
// off, never deleted.

interface MemeToolDependencies {
  readonly memes: Memes;
  readonly clock: () => Date;
}

const phrase = z.strictObject({ phrase: MemePhrase.describe('The meme, as listed.') });

/** `list_memes`: the memes in use now. */
export function listMemes({ memes }: MemeToolDependencies) {
  return adminTool({
    name: 'list_memes',
    title: 'List memes in use',
    description:
      'Lists the memes the AI may use now (approved in the last 4 weeks and not turned off), ' +
      'newest first.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({
      version: 1,
      memes: (await memes.listInUse()).map(
        ({ phrase, background, meaning, styles, source, approvedAt }) => ({
          phrase,
          background,
          meaning,
          styles,
          source,
          approvedAt: approvedAt.toISOString(),
        }),
      ),
    }),
  });
}

/** `add_memes`: adds approved memes, one batch of memes/approved.json per call. */
export function addMemes({ memes, clock }: MemeToolDependencies) {
  return adminTool({
    name: 'add_memes',
    title: 'Add approved memes',
    description:
      'Adds memes the admin approved to the library. To import memes/approved.json, call it ' +
      'once per batch with that batch’s approvedAt. A phrase the library already has is left ' +
      'unchanged, so importing the same batch again changes nothing.',
    changes: true,
    input: z.strictObject({
      memes: z.array(MemeDraft).min(1).max(100),
      approvedAt: z.iso
        .datetime({ offset: true })
        .optional()
        .describe('When the admin approved them; leave it out for now. Used for 4 weeks.'),
    }),
    run: async (input) => {
      const approvedAt = input.approvedAt === undefined ? clock() : new Date(input.approvedAt);
      return { version: 1, ...(await memes.addApproved({ memes: input.memes, approvedAt })) };
    },
  });
}

/** `turn_off_meme`: the AI stops using a meme. */
export function turnOffMeme({ memes }: MemeToolDependencies) {
  return adminTool({
    name: 'turn_off_meme',
    title: 'Turn a meme off',
    description:
      'Stops the AI from using a meme, e.g. one in poor taste. It stays in the library and can ' +
      'be turned back on.',
    changes: true,
    input: phrase,
    run: async (input) => {
      await memes.turnOff(input.phrase);
      return { version: 1, turnedOff: input.phrase };
    },
  });
}

/** `turn_on_meme`: the AI may use a turned-off meme again. */
export function turnOnMeme({ memes }: MemeToolDependencies) {
  return adminTool({
    name: 'turn_on_meme',
    title: 'Turn a meme back on',
    description:
      'Lets the AI use a turned-off meme again. It is still used only in the 4 weeks after ' +
      'its approval.',
    changes: true,
    input: phrase,
    run: async (input) => {
      await memes.turnOn(input.phrase);
      return { version: 1, turnedOn: input.phrase };
    },
  });
}

/** Every meme tool. */
export const memeTools = (deps: MemeToolDependencies) => [
  listMemes(deps),
  addMemes(deps),
  turnOffMeme(deps),
  turnOnMeme(deps),
];
