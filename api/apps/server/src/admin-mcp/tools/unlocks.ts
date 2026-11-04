import {
  GiftPieceEdit,
  MemberId,
  UnlockGift,
  type GiftPiece,
  type GiftsAdmin,
  UnlockRuleEdit,
  type UnlocksAdmin,
  type UnlockRule,
} from '@wildcard/unlocks';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// How the character editor's stores, props and clothing pieces unlock: each after a number of
// 练了 check-ins in its sports. A change applies to the next read of each member's unlocks; what a member already
// unlocked stays. Rules are never deleted.

interface UnlockToolDependencies {
  readonly unlocks: UnlocksAdmin;
  readonly gifts: GiftsAdmin;
}

const shown = (rules: readonly UnlockRule[]) => ({
  version: 1,
  rules: rules.map(({ countsFrom, ...rule }) => ({
    ...rule,
    countsFrom: countsFrom.toISOString(),
  })),
});

/** `get_unlock_rules`: every rule now. */
export function getUnlockRules({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'get_unlock_rules',
    title: 'Read the unlock rules',
    description:
      'Shows how each store on the character editor’s 商店街, each prop and each clothing ' +
      'piece with a rule unlocks: kind (store, prop or piece), id, sports (empty = any sport), ' +
      'after (练了 check-ins needed), countsFrom (only check-ins made from then count) and, for a ' +
      'limited piece, switchId (only check-ins made while that switch is on count, see ' +
      'get_switches). ' +
      'Starters (WARM-UP, the tumbler, the dumbbell) and pieces without a rule (they come ' +
      'with their store) are open to everyone.',
    changes: false,
    input: z.strictObject({}),
    run: async () => shown(await unlocks.rules()),
  });
}

/** `put_unlock_rule`: adds a rule, or changes the sports or count of one. */
export function putUnlockRule({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'put_unlock_rule',
    title: 'Add or change an unlock rule',
    description:
      'Adds a rule for a store, prop or piece, or changes the sports, count or switch of one. A piece ' +
      'with a rule stays locked in its store until earned. A new rule counts check-ins made ' +
      'from now; a changed one keeps its start. Members who already unlocked it keep it. Only ' +
      'the id’s shape is checked, and a rule is never deleted, so use an id the app’s art has ' +
      '(one it doesn’t is ignored by the app). Returns every rule now.',
    changes: true,
    input: UnlockRuleEdit,
    run: async (edit) => shown(await unlocks.putRule(edit)),
  });
}

/** `give_unlocks`: opens stores, props and pieces for one member, whatever they trained. */
export function giveUnlocks({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'give_unlocks',
    title: 'Give a member stores, props and pieces',
    description:
      'Opens the named stores, props and pieces (each one with an unlock rule) for one member now, as ' +
      'if they had earned them, or every one when items is left out; for testing, or to make ' +
      'up for check-ins that could not count. What they already hold stays. An unlock is never ' +
      'taken back. Returns everything the member holds.',
    changes: true,
    input: UnlockGift,
    run: async (gift, { admin }) => ({
      version: 1,
      unlocks: (await unlocks.give(gift, MemberId.parse(admin))).map(
        ({ unlockedAt, ...unlock }) => ({ ...unlock, unlockedAt: unlockedAt.toISOString() }),
      ),
    }),
  });
}

const pool = (pieces: readonly GiftPiece[]) => ({ version: 1, pieces });

/** `get_gift_pieces`: the pieces a squad's coach may give. */
export function getGiftPieces({ gifts }: UnlockToolDependencies) {
  return adminTool({
    name: 'get_gift_pieces',
    title: 'Read the coach gift pool',
    description:
      'Shows the clothing pieces a squad’s coach may give a member: pieces no store sells, each ' +
      'by its id in the app’s art and whether it is offered now. A member given one keeps it in ' +
      'their wardrobe, never in a store.',
    changes: false,
    input: z.strictObject({}),
    run: async () => pool(await gifts.pieces()),
  });
}

/** `put_gift_piece`: adds a piece to the coach gift pool, or offers or withdraws one. */
export function putGiftPiece({ gifts }: UnlockToolDependencies) {
  return adminTool({
    name: 'put_gift_piece',
    title: 'Add or change a coach gift piece',
    description:
      'Adds a clothing piece a squad’s coach may give, or offers or withdraws one (offered = ' +
      'false stops new gifts; members who have it keep it). A piece is never deleted. Only the ' +
      'id’s shape is checked, so use an id the app’s art has and no store sells. Returns the ' +
      'pool now.',
    changes: true,
    input: GiftPieceEdit,
    run: async (edit) => pool(await gifts.putPiece(edit)),
  });
}

export const unlockTools = (deps: UnlockToolDependencies) => [
  getUnlockRules(deps),
  putUnlockRule(deps),
  giveUnlocks(deps),
  getGiftPieces(deps),
  putGiftPiece(deps),
];
