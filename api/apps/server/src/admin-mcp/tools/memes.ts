import { MemeDraft, MemePhrase, type Memes } from '@wildcard/memes';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The meme library's tools: what the AI writing a 今日请假条 may draw on. Memes are turned
// off, never deleted.

interface MemeToolDependencies {
  readonly memes: Memes;
  readonly clock: () => Date;
}

const phrase = z.strictObject({ phrase: MemePhrase.describe('The meme, as listed.') });

const expiry = z.iso.datetime({ offset: true });

/** `list_memes`: the memes in use now, or with `all` every meme in the library. */
export function listMemes({ memes }: MemeToolDependencies) {
  return adminTool({
    name: 'list_memes',
    title: 'List memes',
    description:
      'Lists the memes the AI may use now (approved, not expired and not turned off), newest ' +
      'first, each with when it expires (null: it stays in use until turned off). With all, ' +
      'lists every meme in the library, expired and turned off included, to find one to extend ' +
      'or turn back on.',
    changes: false,
    input: z.strictObject({
      all: z
        .boolean()
        .optional()
        .describe('List every meme, not only the ones in use. Leave it out for the ones in use.'),
    }),
    run: async (input) => ({
      version: 1,
      memes: (input.all === true
        ? await memes.listAll()
        : (await memes.listInUse()).map((meme) => ({ ...meme, turnedOffAt: null }))
      ).map(
        ({ phrase, background, meaning, styles, source, approvedAt, expiresAt, turnedOffAt }) => ({
          phrase,
          background,
          meaning,
          styles,
          source,
          approvedAt: approvedAt.toISOString(),
          expiresAt: expiresAt?.toISOString() ?? null,
          turnedOffAt: turnedOffAt?.toISOString() ?? null,
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
      'unchanged, its expiry included (set_meme_expiry changes that), so importing the same ' +
      'batch again changes nothing. A meme tied to a moment ' +
      'gets expiresAt; one without it stays in use until turned off.',
    changes: true,
    input: z.strictObject({
      memes: z
        .array(
          MemeDraft.extend({
            expiresAt: expiry
              .optional()
              .describe(
                'When it stops being used, e.g. a week on for 「只用一周」. Leave it out for a ' +
                  'meme people keep saying.',
              ),
          }),
        )
        .min(1)
        .max(100),
      approvedAt: expiry
        .optional()
        .describe('When the admin approved them; leave it out for now. Used from then on.'),
    }),
    run: async (input) => {
      const approvedAt = input.approvedAt === undefined ? clock() : new Date(input.approvedAt);
      const approved = input.memes.map(({ expiresAt, ...meme }) =>
        expiresAt === undefined ? meme : { ...meme, expiresAt: new Date(expiresAt) },
      );
      return { version: 1, ...(await memes.addApproved({ memes: approved, approvedAt })) };
    },
  });
}

/** `set_meme_expiry`: sets or clears when a meme stops being used. */
export function setMemeExpiry({ memes }: MemeToolDependencies) {
  return adminTool({
    name: 'set_meme_expiry',
    title: 'Set when a meme expires',
    description:
      'Sets when a meme stops being used, or with null clears it so the meme stays in use ' +
      'until turned off. Giving an expired meme a later expiry, or null, uses it again. The ' +
      'expiry must come after its approval.',
    changes: true,
    input: phrase.extend({
      expiresAt: expiry.nullable().describe('When it stops being used; null for never.'),
    }),
    run: async (input) => {
      const expiresAt = input.expiresAt === null ? null : new Date(input.expiresAt);
      await memes.setExpiry({ phrase: input.phrase, expiresAt });
      return { version: 1, phrase: input.phrase, expiresAt: expiresAt?.toISOString() ?? null };
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
      'Lets the AI use a turned-off meme again. It still stops being used once it expires.',
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
  setMemeExpiry(deps),
  turnOffMeme(deps),
  turnOnMeme(deps),
];
