import {
  localDay,
  type MemberId,
  type Nudge,
  type NudgeKind,
  type SquadId,
} from '../domain/nudge.js';
import { NotASquadmateError, OwnNudgeError, SquadNotJoinedError } from '../errors.js';
import type { Clock, NudgeStore, SquadMembership, TimeZoneOf } from '../ports.js';

export interface SendNudgeInput {
  readonly from: MemberId;
  readonly to: MemberId;
  readonly squad: SquadId;
  readonly kind: NudgeKind;
}

/** Squadmates nudging each other: 催你练 and 好好休息, counted in the daily push. */
export interface Nudges {
  /**
   * Sends a nudge to a squadmate. One of each kind a day from one member to another: a second
   * is `unchanged`, so a retry is safe. Throws `SquadNotJoinedError` when the sender isn't in
   * the squad, `NotASquadmateError` when the receiver isn't, and `OwnNudgeError` for oneself.
   */
  send(input: SendNudgeInput): Promise<'created' | 'unchanged'>;
  /**
   * Who nudged the member in `[since, until)`, by kind, each person once. A nudge counts only
   * while its sender and the member are both still in the squad it was sent in.
   */
  received(input: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
  }): Promise<ReadonlyMap<NudgeKind, ReadonlySet<MemberId>>>;
}

export function createNudges(deps: {
  readonly store: NudgeStore;
  readonly membership: SquadMembership;
  readonly timeZoneOf: TimeZoneOf;
  readonly clock: Clock;
}): Nudges {
  return {
    async send({ from, to, squad, kind }) {
      if (from === to) throw new OwnNudgeError();
      const members = await deps.membership.membersOf(squad);
      if (!members.includes(from)) throw new SquadNotJoinedError(squad);
      if (!members.includes(to)) throw new NotASquadmateError(to);
      const at = deps.clock();
      // A member who hasn't saved a time zone yet counts days in UTC.
      const day = localDay(at, (await deps.timeZoneOf(from)) ?? 'UTC');
      const nudge: Nudge = { from, to, squad, kind, day, at };
      return deps.store.add(nudge);
    },

    async received({ member, since, until }) {
      const [nudges, squads] = await Promise.all([
        deps.store.receivedBy({ member, since, until }),
        deps.membership.squadIdsOf(member),
      ]);
      const membersOf = new Map<SquadId, ReadonlySet<MemberId>>();
      const byKind = new Map<NudgeKind, Set<MemberId>>();
      for (const { from, squad, kind } of nudges) {
        if (!squads.has(squad)) continue;
        let members = membersOf.get(squad);
        if (members === undefined) {
          members = new Set(await deps.membership.membersOf(squad));
          membersOf.set(squad, members);
        }
        if (!members.has(from)) continue;
        byKind.set(kind, (byKind.get(kind) ?? new Set()).add(from));
      }
      return byKind;
    },
  };
}
