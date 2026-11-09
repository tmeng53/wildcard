import type {
  Badge,
  Given,
  HeldBadge,
  Occurrence,
  Reward,
  RewardTriggerEdit,
  TeamPiece,
  Voucher,
} from '../domain/rewards.js';
import type { MemberId } from '../domain/unlocks.js';
import { RewardMissingError, RewardNotTeamGivenError } from '../errors.js';
import type { RewardStore, UnlockStore } from '../ports.js';

/** What the team and events give members, and what each member holds of it. */
export interface Rewards {
  /** The dedicated badges `member` holds, with how many times (×N), the latest got first. */
  badgesOf(member: MemberId): Promise<HeldBadge[]>;
  /** The pieces no store sells that the team or an event gave `member`, the earliest first. */
  teamPiecesOf(member: MemberId): Promise<TeamPiece[]>;
  /**
   * Gives `occurrence`'s member every reward an offered `event` trigger gives for its event; what
   * this occurrence gave before, or a piece they hold, stays as it was. Answers with what it gave.
   */
  happened(occurrence: Occurrence): Promise<Given[]>;
}

/** The catalog and triggers, for admins. */
export interface RewardsAdmin {
  badges(): Promise<Badge[]>;
  /** Adds or changes a badge and answers with every badge now. */
  putBadge(badge: Badge): Promise<Badge[]>;
  vouchers(): Promise<Voucher[]>;
  /** Adds or changes a voucher and answers with every voucher now. */
  putVoucher(voucher: Voucher): Promise<Voucher[]>;
  /** Adds or changes an `event` or `team` trigger and answers with every reward now. */
  putTrigger(edit: RewardTriggerEdit): Promise<Reward[]>;
  /**
   * `admin` gives `member` `reward`, which has an offered `team` trigger; false for a piece they
   * hold already. Each badge or voucher given is one more.
   */
  give(grant: {
    readonly member: MemberId;
    readonly reward: Given;
    readonly admin: MemberId;
  }): Promise<boolean>;
}

export function createRewards(deps: {
  readonly store: RewardStore;
  /** Where every reward and its triggers are read from. */
  readonly unlocks: Pick<UnlockStore, 'rewards'>;
  readonly clock: () => Date;
}): Rewards & RewardsAdmin {
  const named = ({ kind, id }: Given) => `${kind} ${id}`;
  return {
    badgesOf: (member) => deps.store.badgesOf(member),
    teamPiecesOf: (member) => deps.store.teamPiecesOf(member),

    async happened(occurrence) {
      const rewards = await deps.store.givenBy(occurrence.event);
      return deps.store.grantFor(occurrence, rewards);
    },

    badges: () => deps.store.badges(),

    async putBadge(badge) {
      await deps.store.putBadge(badge);
      return deps.store.badges();
    },

    vouchers: () => deps.store.vouchers(),

    async putVoucher(voucher) {
      await deps.store.putVoucher(voucher);
      return deps.store.vouchers();
    },

    async putTrigger(edit) {
      if (edit.kind !== 'piece' && !(await deps.store.exists(edit))) {
        throw new RewardMissingError(named(edit));
      }
      await deps.store.putTrigger(edit);
      return deps.unlocks.rewards();
    },

    async give({ member, reward, admin }) {
      if (!(await deps.store.teamGives(reward))) throw new RewardNotTeamGivenError(named(reward));
      return deps.store.grantByTeam({ member, reward, admin, at: deps.clock() });
    },
  };
}
