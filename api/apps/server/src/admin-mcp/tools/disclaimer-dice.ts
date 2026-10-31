import { DiceLineList, MemberId, type DiceLinesAdmin } from '@wildcard/disclaimer-drafts';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The 请假条 dice: the ready-made lines the app rolls when the AI can't write. The public catalog
// serves them, so a change reaches phones within about a minute of their next catalog read, with
// no app release; each change is logged with the whole new list.

interface DisclaimerDiceToolDependencies {
  readonly dice: DiceLinesAdmin;
}

/** `get_disclaimer_dice`: every dice line, in each language. */
export function getDisclaimerDice({ dice }: DisclaimerDiceToolDependencies) {
  return adminTool({
    name: 'get_disclaimer_dice',
    title: 'Read the 请假条 dice lines',
    description:
      'Shows the ready-made 请假条 lines the app rolls when AI drafts can’t be written (offline, ' +
      'drafts off, no AI consent), each in Simplified Chinese, English and Traditional Chinese.',
    changes: false,
    input: z.strictObject({}),
    run: async () => dice.current(),
  });
}

/** `change_disclaimer_dice`: replaces the whole list. */
export function changeDisclaimerDice({ dice }: DisclaimerDiceToolDependencies) {
  return adminTool({
    name: 'change_disclaimer_dice',
    title: 'Change the 请假条 dice lines',
    description:
      'Replaces every dice line with `lines` (3 to 50, each up to 60 characters in every ' +
      'language, no two alike): read them first, then send the whole list with your edits. The app rolls ' +
      'three different lines at a time and picks the new list up on its next catalog read. ' +
      'Returns the lines now.',
    changes: true,
    input: z.strictObject({ lines: DiceLineList }),
    run: async ({ lines }, { admin }) => dice.replace(lines, MemberId.parse(admin)),
  });
}

export const disclaimerDiceTools = (deps: DisclaimerDiceToolDependencies) => [
  getDisclaimerDice(deps),
  changeDisclaimerDice(deps),
];
