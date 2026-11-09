import { AdoptionKind, FeedbackId, type Adoption } from '@wildcard/feedback';
import {
  BadgeEdit,
  GivenKind,
  MemberId,
  RewardTriggerEdit,
  VoucherEdit,
  type Given,
  type RewardsAdmin,
} from '@wildcard/unlocks';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// What the Wildcard team gives: dedicated badges (捉虫队, 点子王, drawn as tickets, never the weekly
// awards' badges), 高级券 vouchers and pieces no store sells, each by its `team` or `event`
// trigger; and adopting feedback we used, which sets off its event. Nothing here is automatic: an
// admin adopts a message only after checking the bug is real or the idea's change merged.

interface RewardToolDependencies {
  readonly rewards: RewardsAdmin;
  /** Adopts a message and thanks its sender, in the tool's transaction. */
  readonly adopt: (input: {
    readonly feedback: string;
    readonly kind: AdoptionKind;
    readonly admin: string;
  }) => Promise<{
    readonly adoption: Adoption;
    readonly fresh: boolean;
    readonly given: readonly Given[];
  }>;
}

/** `get_badges`: every dedicated badge and voucher. */
export function getBadges({ rewards }: RewardToolDependencies) {
  return adminTool({
    name: 'get_badges',
    title: 'Read the badges and vouchers',
    description:
      'Shows every dedicated badge (the team’s own, drawn as a ticket: id, names in zh-Hans, ' +
      'zh-Hant and en, SF Symbol glyph, tone and offered) and every 高级券 voucher (id, ' +
      'premiumDays of squad premium once redeemed, offered). How each is got is its triggers ' +
      '(get_rewards). The weekly awards’ badges are another catalog (get_weekly_award_settings).',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({
      version: 1,
      badges: await rewards.badges(),
      vouchers: await rewards.vouchers(),
    }),
  });
}

/** `put_badge`: adds a dedicated badge, or changes one. */
export function putBadge({ rewards }: RewardToolDependencies) {
  return adminTool({
    name: 'put_badge',
    title: 'Add or change a dedicated badge',
    description:
      'Adds a dedicated badge or changes its names, glyph, tone or offered. It is never ' +
      'deleted: offered = false stops new grants, and who has it keeps it. A member may hold one ' +
      'many times (×N). Give it a way to be got with put_reward_trigger. Returns every badge.',
    changes: true,
    input: BadgeEdit,
    run: async (badge) => ({ version: 1, badges: await rewards.putBadge(badge) }),
  });
}

/** `put_voucher`: adds a voucher, or changes one. */
export function putVoucher({ rewards }: RewardToolDependencies) {
  return adminTool({
    name: 'put_voucher',
    title: 'Add or change a voucher',
    description:
      'Adds a 高级券 voucher (premiumDays of squad premium, redeemed by any member who holds one ' +
      'once premium exists) or changes one. It is never deleted: offered = false stops new ' +
      'grants. Give it a way to be got with put_reward_trigger. Returns every voucher.',
    changes: true,
    input: VoucherEdit,
    run: async (voucher) => ({ version: 1, vouchers: await rewards.putVoucher(voucher) }),
  });
}

/** `put_reward_trigger`: adds or changes a reward's `event` or `team` trigger. */
export function putRewardTrigger({ rewards }: RewardToolDependencies) {
  return adminTool({
    name: 'put_reward_trigger',
    title: 'Add or change an event or team trigger',
    description:
      'Says that a piece, badge or voucher is got by events (way event: the events, such as ' +
      'bug-adopted and idea-adopted, each give it once per time they happen) or by the team ' +
      '(way team: give_reward gives it), or changes whether that way still gives it (offered). ' +
      'A piece is named by its id in the app’s art (only its shape is checked); a badge or ' +
      'voucher must be added first (put_badge, put_voucher). A trigger is never deleted. ' +
      'Returns every reward with its triggers.',
    changes: true,
    input: RewardTriggerEdit,
    run: async (edit) => ({ version: 1, rewards: await rewards.putTrigger(edit) }),
  });
}

/** `give_reward`: the team gives one member a piece, badge or voucher. */
export function giveReward({ rewards }: RewardToolDependencies) {
  return adminTool({
    name: 'give_reward',
    title: 'Give a member a team reward',
    description:
      'Gives one member a piece, badge or voucher that has an offered team trigger, now, as the ' +
      'Wildcard team. A piece they hold already stays as it was (given: false); each badge or ' +
      'voucher given is one more. Never taken back. For feedback we used, use adopt_feedback.',
    changes: true,
    input: z.strictObject({
      member: MemberId.describe('The member’s id.'),
      kind: GivenKind,
      id: z.string().min(1).max(48),
    }),
    run: async ({ member, kind, id }, { admin }) => ({
      version: 1,
      given: await rewards.give({
        member,
        reward: { kind, id },
        admin: MemberId.parse(admin),
      }),
    }),
  });
}

/** `adopt_feedback`: records that we used a message and thanks its sender. */
export function adoptFeedbackTool({ adopt }: RewardToolDependencies) {
  return adminTool({
    name: 'adopt_feedback',
    title: 'Adopt feedback and thank its sender',
    description:
      'Records that we used a message from 意见反馈 (its id, as in the feedback issue): kind bug ' +
      'once the bug is confirmed real (reproduced or fixed), kind idea once the change shipping ' +
      'it merged. Never before checking. Its sender then gets what the event bug-adopted or ' +
      'idea-adopted gives (get_rewards; each duplicate reporter is adopted on their own message) ' +
      'and a thanks notice. A message is adopted once: again changes nothing (fresh: false). ' +
      'Returns the adoption and what it gave.',
    changes: true,
    input: z.strictObject({
      feedback: FeedbackId.describe('The message’s id.'),
      kind: AdoptionKind,
    }),
    run: async ({ feedback, kind }, { admin }) => {
      const { adoption, fresh, given } = await adopt({ feedback, kind, admin });
      return {
        version: 1,
        adoption: { ...adoption, at: adoption.at.toISOString() },
        fresh,
        given,
      };
    },
  });
}

export const rewardTools = (deps: RewardToolDependencies) => [
  getBadges(deps),
  putBadge(deps),
  putVoucher(deps),
  putRewardTrigger(deps),
  giveReward(deps),
  adoptFeedbackTool(deps),
];
