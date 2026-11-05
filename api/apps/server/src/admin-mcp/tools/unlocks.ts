import {
  MemberId,
  PieceEdit,
  StoreEdit,
  UnlockGift,
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
      'after (练了 check-ins needed) and countsFrom (only check-ins made from then count). A rule ' +
      'counts only check-ins made while its store’s and piece’s switches are on (get_stores, ' +
      'get_pieces). Starter pieces (get_pieces) and the tumbler and dumbbell need no rule.',
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
      'Adds a rule for a store, prop or piece, or changes the sports or count of one. A piece ' +
      'with a rule stays locked in its store until earned; when it is out follows its store and ' +
      'piece (put_store, put_piece). A new rule counts check-ins made ' +
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

/** `get_stores`: every store on the 商店街. */
export function getStores({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'get_stores',
    title: 'Read the stores',
    description:
      'Shows every store on the character editor’s 商店街, in its order: id, position, switchId ' +
      '(open only while that switch is on, see get_switches; none for always) and offered. A ' +
      'closed store shows each member only the pieces they own. Whether a member has earned a ' +
      'store is its unlock rule (get_unlock_rules).',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({ version: 1, stores: await unlocks.stores() }),
  });
}

/** `put_store`: adds a store, or replaces one whole. */
export function putStore({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'put_store',
    title: 'Add or change a store',
    description:
      'Adds a store, or replaces every field of one (read it with get_stores first: null ' +
      'switchId opens it always). A store needs its art in the app; builds without it leave it ' +
      'out. Set offered to false to retire one. Members see it on their next read. Returns ' +
      'every store now.',
    changes: true,
    input: StoreEdit,
    run: async (edit) => ({ version: 1, stores: await unlocks.putStore(edit) }),
  });
}

/** `get_pieces`: every clothing piece. */
export function getPieces({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'get_pieces',
    title: 'Read the clothing pieces',
    description:
      'Shows every clothing piece: id, storeId, slot, starter (everyone has it while it is out; ' +
      'any other needs an unlock rule), switchId (its own switch, apart from its store’s) and ' +
      'offered. A piece is out while its store is open and its own switch is on; what a member ' +
      'owns stays theirs all year.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({ version: 1, pieces: await unlocks.pieces() }),
  });
}

/** `put_piece`: adds a piece, or replaces one whole. */
export function putPiece({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'put_piece',
    title: 'Add or change a clothing piece',
    description:
      'Adds a piece to a store, or replaces every field of one (read it with get_pieces first). ' +
      'A piece that is not a starter also needs an unlock rule (put_unlock_rule), or it never ' +
      'shows. A piece needs its art in the app. Set offered to false to retire one: nobody can ' +
      'earn it any more and only those who own it see it. Returns every piece now.',
    changes: true,
    input: PieceEdit,
    run: async (edit) => ({ version: 1, pieces: await unlocks.putPiece(edit) }),
  });
}

export const unlockTools = (deps: UnlockToolDependencies) => [
  getUnlockRules(deps),
  putUnlockRule(deps),
  giveUnlocks(deps),
  getStores(deps),
  putStore(deps),
  getPieces(deps),
  putPiece(deps),
];
