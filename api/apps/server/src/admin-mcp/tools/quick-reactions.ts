import { MemberId, QuickReactions, type QuickReactionsAdmin } from '@wildcard/check-ins';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The reaction bar's quick emoji, in order. Any one emoji is still a reaction; these are the ones
// the bar offers first. The public catalog serves them, so a change reaches phones on their next
// catalog read, with no app release; each change is logged with the whole new list.

interface QuickReactionToolDependencies {
  readonly reactions: QuickReactionsAdmin;
}

/** `get_quick_reactions`: the reaction bar's emoji now. */
export function getQuickReactions({ reactions }: QuickReactionToolDependencies) {
  return adminTool({
    name: 'get_quick_reactions',
    title: 'Read the quick reactions',
    description:
      'Shows the emoji the reaction bar on 动态 offers first, in order (the 6pm push’s long-press ' +
      'view keeps the six the app shipped with).',
    changes: false,
    input: z.strictObject({}),
    run: async () => reactions.current(),
  });
}

/** `change_quick_reactions`: replaces the whole list. */
export function changeQuickReactions({ reactions }: QuickReactionToolDependencies) {
  return adminTool({
    name: 'change_quick_reactions',
    title: 'Change the quick reactions',
    description:
      'Replaces the reaction bar’s emoji with `emoji`, in order: 1 to 6 different ones (the bar fits six), each a ' +
      'single emoji. Members can still react with any emoji. Apps pick the list up on their ' +
      'next catalog read. Returns the list now.',
    changes: true,
    input: z.strictObject({ emoji: QuickReactions.shape.emoji }),
    run: async ({ emoji }, { admin }) => reactions.replace(emoji, MemberId.parse(admin)),
  });
}

export const quickReactionTools = (deps: QuickReactionToolDependencies) => [
  getQuickReactions(deps),
  changeQuickReactions(deps),
];
