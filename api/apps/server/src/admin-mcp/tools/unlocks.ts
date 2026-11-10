import {
  GIFT_LINE_LIMIT,
  GiftPieceEdit,
  MemberId,
  PieceEdit,
  StoreEdit,
  PieceId,
  UnlockGift,
  type CoachGift,
  type GiftPiece,
  type GiftsAdmin,
  UnlockRuleEdit,
  type UnlocksAdmin,
  type UnlockRule,
} from '@wildcard/unlocks';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// How the character editor's stores, props and clothing pieces unlock: each after 训练 in its sports
// on a number of different days (many on one day count once). A change applies to the next read of each member's unlocks; what a member already
// unlocked stays. Rules are never deleted.

interface UnlockToolDependencies {
  readonly unlocks: UnlocksAdmin;
  readonly gifts: GiftsAdmin;
  /**
   * Gives a piece from the squad's coach in an admin's name, keeping every gift rule (one a
   * member a week, offered, not owned) and that the member is in the squad and it has a coach.
   */
  readonly giveGift: (input: {
    readonly squad: string;
    readonly member: string;
    readonly piece: string;
    readonly line: string;
    readonly admin: string;
  }) => Promise<CoachGift>;
}

const shown = (rules: readonly UnlockRule[]) => ({
  version: 1,
  rules: rules.map(({ countsFrom, ...rule }) => ({
    ...rule,
    countsFrom: countsFrom.toISOString(),
  })),
});

/** `get_rewards`: every reward and every way it is got. */
export function getRewards({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'get_rewards',
    title: 'Read the rewards and their triggers',
    description:
      'Shows everything a member can get (a store, prop, piece, badge or voucher) and every way ' +
      'they get it, one trigger per way: training (sports, empty = any; after = days with 训练, ' +
      'counted from countsFrom; change with put_unlock_rule), coach (a squad’s AI coach may ' +
      'give it, one a member a week; offered and the description its model reads; change with ' +
      'put_gift_piece), team (only the Wildcard team gives it, with give_reward) or event (the ' +
      'named events give it, such as bug-adopted and idea-adopted from adopt_feedback; change ' +
      'team and event triggers with put_reward_trigger). give_unlocks gives what has a training ' +
      'trigger. A training trigger with offered false is retired and opens nothing more (every ' +
      'prop’s, since props are everyone’s). Starter pieces need none. Badges and vouchers ' +
      'themselves: get_badges.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({
      version: 1,
      rewards: (await unlocks.rewards()).map((reward) => ({
        ...reward,
        triggers: reward.triggers.map((trigger) =>
          trigger.kind === 'training'
            ? { ...trigger, countsFrom: trigger.countsFrom.toISOString() }
            : trigger,
        ),
      })),
    }),
  });
}

/** `put_unlock_rule`: adds a rule, or changes the sports or count of one. */
export function putUnlockRule({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'put_unlock_rule',
    title: 'Add or change an unlock rule',
    description:
      'Adds a rule for a store or piece, or changes the sports or count of one. A piece ' +
      'with a rule stays locked in its store until earned; when it is out follows its store and ' +
      'piece (put_store, put_piece). A new rule counts check-ins made ' +
      'from now; a changed one keeps its start, and a retired one comes back. Members who ' +
      'already unlocked it keep it. Only ' +
      'the id’s shape is checked, and a rule is never deleted, so use an id the app’s art has ' +
      '(one it doesn’t is ignored by the app). Returns every rule now.',
    changes: true,
    input: UnlockRuleEdit,
    run: async (edit) => shown(await unlocks.putRule(edit)),
  });
}

/** `give_unlocks`: opens stores and pieces for one member, whatever they trained. */
export function giveUnlocks({ unlocks }: UnlockToolDependencies) {
  return adminTool({
    name: 'give_unlocks',
    title: 'Give a member stores and pieces',
    description:
      'Opens the named stores and pieces (each one with an unlock rule) for one member now, as ' +
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
      'store is its training trigger (get_rewards).',
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
      'shows; a starter has no unlock rule (a rule left on one would still unlock it, and old ' +
      'builds would show it boxed). A piece needs its art in the app. Set offered to false to retire one: nobody can ' +
      'earn it any more and only those who own it see it. Returns every piece now.',
    changes: true,
    input: PieceEdit,
    run: async (edit) => ({ version: 1, pieces: await unlocks.putPiece(edit) }),
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
      'their wardrobe, never in a store. Each has a description, what the coach’s model reads ' +
      'before giving it.',
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
      'false stops new gifts; members who have it keep it), with its description for the ' +
      'coach’s model (left out keeps the one it has). A piece is never deleted. Only the ' +
      'id’s shape is checked, so use an id the app’s art has and no store sells. Returns the ' +
      'pool now.',
    changes: true,
    input: GiftPieceEdit,
    run: async (edit) => pool(await gifts.putPiece(edit)),
  });
}

/** `give_gift`: gives a member a piece from their squad's coach, with an admin's own line. */
export function giveGift({ giveGift: give }: UnlockToolDependencies) {
  return adminTool({
    name: 'give_gift',
    title: 'Give a member a coach gift',
    description:
      'Gives a member a piece from the gift pool (get_gift_pieces) in the name of their squad’s ' +
      'coach, with your own line, which only they see, on the coach page. The same rules as the ' +
      'coach’s own gifts: an offered piece they don’t have, and at most one gift a member a week ' +
      '(on the squad’s clock); a refused gift says why. Logged as yours. Never taken back.',
    changes: true,
    input: z.strictObject({
      squad: z.uuid().describe('The squad’s id; its coach gives it.'),
      member: z.uuid().describe('The member’s id; they must be in the squad now.'),
      piece: PieceId.describe('The piece’s id in the gift pool.'),
      line: z
        .string()
        .trim()
        .min(1)
        .max(GIFT_LINE_LIMIT)
        .describe(
          `What the coach says with it, in the member’s language, up to ${String(GIFT_LINE_LIMIT)} characters.`,
        ),
    }),
    run: async (input, { admin }) => {
      const gift = await give({ ...input, admin });
      return {
        version: 1,
        gift: { ...gift, givenAt: gift.givenAt.toISOString() },
      };
    },
  });
}

export const unlockTools = (deps: UnlockToolDependencies) => [
  getRewards(deps),
  putUnlockRule(deps),
  giveUnlocks(deps),
  getStores(deps),
  putStore(deps),
  getPieces(deps),
  putPiece(deps),
  getGiftPieces(deps),
  putGiftPiece(deps),
  giveGift(deps),
];
