import type { LocalDay, MemberId, Nudge, NudgeKind, SquadId } from './domain/nudge.js';

/** Where nudges are kept. They are never changed once sent. */
export interface NudgeStore {
  /** Saves a nudge, unless the same one (sender, receiver, kind and day) is there already. */
  add(nudge: Nudge): Promise<'created' | 'unchanged'>;
  /** The nudges `member` got in `[since, until)`, of `kind` when given, oldest first. */
  receivedBy(query: {
    readonly member: MemberId;
    readonly since: Date;
    readonly until: Date;
    readonly kind?: NudgeKind;
  }): Promise<Nudge[]>;
  /** The nudges of `kind` `member` sent in `squad` on `day` (their own clock), oldest first. */
  sentBy(query: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly day: LocalDay;
    readonly kind: NudgeKind;
  }): Promise<Nudge[]>;
}

/** Who is in which squad now. The squads module keeps that; nudges only ask. */
export interface SquadMembership {
  /** The squads `member` is in now. */
  squadIdsOf(member: MemberId): Promise<ReadonlySet<SquadId>>;
  /** The members in `squad` now, in the order they joined. */
  membersOf(squad: SquadId): Promise<MemberId[]>;
}

/** The member's IANA time zone, from their profile, or `undefined` before they save one. */
export type TimeZoneOf = (member: MemberId) => Promise<string | undefined>;

/** The current time. */
export type Clock = () => Date;
