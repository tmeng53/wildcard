import {
  createPostgresCoachHiring,
  SquadId as CoachSquadId,
  type CoachGifting,
} from '@wildcard/coach';
import { createPostgresSquadStore, SquadId } from '@wildcard/squads';
import { momentAt, mondayOf, wallClockAt } from '@wildcard/time-zones';
import {
  CoachId,
  createCoachGifts,
  createPostgresGiftStore,
  GiftMemberNotInSquadError,
  GiftNoCoachError,
  MemberId,
  PieceId,
  type CoachGift,
  type CoachGifts,
  type GivenBy,
} from '@wildcard/unlocks';

import type { Database } from '../ports.js';

// A coach's gifts span modules: the unlocks module keeps the pool and who got what, and the
// squads module the clock a member's gift week runs on (the squad's, as the coach's day does).
// At most one gift a member a week, enforced by the unlocks module whoever gives it (the coach
// on its daily wake, or an admin in its name; Tracy, 2026-11-08).

/** When the squad's week began at `now`, on its clock (小队时区). */
export type SquadWeekStart = (squad: string, now: Date) => Promise<Date>;

/** A squad's week start from its time zones. */
export function squadWeekStart(
  timeZonesAt: (squads: readonly string[], moment: Date) => Promise<(squad: string) => string>,
): SquadWeekStart {
  return async (squad, now) => {
    const zone = (await timeZonesAt([squad], now))(squad);
    return momentAt({ day: mondayOf(wallClockAt(now, zone).day), hour: 0, zone });
  };
}

/** Gives a piece from the squad's coach, with its line, as the coach or an admin. */
export async function giveCoachGift(
  deps: { readonly gifts: Pick<CoachGifts, 'give'>; readonly weekStart: SquadWeekStart },
  input: {
    readonly squad: string;
    readonly member: string;
    readonly coach: string;
    readonly piece: string;
    readonly line: string;
    readonly givenBy: GivenBy;
    readonly admin?: string;
    readonly now: Date;
  },
): Promise<CoachGift> {
  return deps.gifts.give({
    member: MemberId.parse(input.member),
    piece: PieceId.parse(input.piece),
    coach: CoachId.parse(input.coach),
    squad: input.squad,
    line: input.line,
    givenBy: input.givenBy,
    ...(input.admin === undefined ? {} : { admin: MemberId.parse(input.admin) }),
    weekStart: await deps.weekStart(input.squad, input.now),
  });
}

/** The coach's gifting, as its daily wake uses it. */
export function coachGifting(deps: {
  readonly gifts: Pick<CoachGifts, 'give' | 'of' | 'offered'>;
  readonly weekStart: SquadWeekStart;
  readonly clock: () => Date;
}): CoachGifting {
  return {
    options: async ({ squad, members }) => {
      const now = deps.clock();
      const [pool, weekStart] = await Promise.all([
        deps.gifts.offered(),
        deps.weekStart(squad, now),
      ]);
      const open = new Map<string, readonly string[]>();
      for (const member of members) {
        const had = await deps.gifts.of(MemberId.parse(member));
        if (had.some(({ givenAt }) => givenAt >= weekStart)) continue;
        open.set(
          member,
          had.map(({ piece }) => piece),
        );
      }
      return {
        pool: pool.map(({ id, description }) => ({
          id,
          ...(description === undefined ? {} : { description }),
        })),
        open,
      };
    },
    given: async ({ squad, coach, members, since }) => {
      const given = await Promise.all(
        members.map(async (member) =>
          (await deps.gifts.of(MemberId.parse(member)))
            .filter((gift) => gift.squad === squad && gift.coach === coach && gift.givenAt >= since)
            .map((gift) => ({
              member,
              piece: gift.piece,
              ...(gift.line === undefined ? {} : { line: gift.line }),
              at: gift.givenAt,
              ...(gift.opened === undefined ? {} : { opened: { worn: gift.opened.worn } }),
            })),
        ),
      );
      return given.flat().sort((a, b) => a.at.getTime() - b.at.getTime());
    },
    give: async ({ squad, member, coach, piece, line }) => {
      try {
        await giveCoachGift(deps, {
          squad,
          member,
          coach,
          piece,
          line,
          givenBy: 'coach',
          now: deps.clock(),
        });
        return undefined;
      } catch (error) {
        return error instanceof Error ? error.message : String(error);
      }
    },
  };
}

/**
 * `give_gift`'s giving, on the admin tool's transaction: from the squad's coach now, to a member
 * in the squad now, in the admin's name.
 */
export function giveGiftAsAdmin(scope: Database, weekStart: SquadWeekStart) {
  return async ({
    squad,
    member,
    piece,
    line,
    admin,
  }: {
    readonly squad: string;
    readonly member: string;
    readonly piece: string;
    readonly line: string;
    readonly admin: string;
  }): Promise<CoachGift> => {
    const inSquad = await createPostgresSquadStore(scope).membersOf(SquadId.parse(squad));
    if (!inSquad.some((each) => each === member)) throw new GiftMemberNotInSquadError();
    const hired = await createPostgresCoachHiring(scope).coachOf(CoachSquadId.parse(squad));
    if (hired === undefined) throw new GiftNoCoachError();
    return giveCoachGift(
      { gifts: createCoachGifts({ store: createPostgresGiftStore(scope) }), weekStart },
      {
        squad,
        member,
        coach: hired.coach,
        piece,
        line,
        givenBy: 'admin',
        admin,
        now: new Date(),
      },
    );
  };
}
