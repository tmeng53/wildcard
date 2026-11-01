import {
  SquadId as CheckInSquad,
  WeekStart as CheckInWeek,
  type CheckInRecord,
  type CheckIns,
} from '@wildcard/check-ins';
import type { SquadWeekSource, WeekCheckIn } from '@wildcard/coach';
import type { Members } from '@wildcard/members';
import type { Sports } from '@wildcard/sports';

// The coach across modules: a squad's week from check-ins, its members' nicknames from members
// and sports' names from sports, in the shape the coach reads.

/** A squad's week as the coach sees it, up to `now`. */
export function coachSquadWeek(deps: {
  readonly checkIns: CheckIns;
  readonly members: Members;
  readonly sports: Sports;
  readonly clock: () => Date;
}): SquadWeekSource {
  return async ({ squad, weekStart }) => {
    const week = await deps.checkIns.squadWeekCheckIns({
      squad: CheckInSquad.parse(squad),
      weekStart: CheckInWeek.parse(weekStart),
      before: deps.clock(),
    });
    const [squadmates, catalog] = await Promise.all([
      deps.members.squadmates(week.members.map(({ member }) => member)),
      deps.sports.catalog(),
    ]);
    const sportNames = new Map(
      catalog.categories.flatMap(({ sports }) => sports.map(({ id, names }) => [id, names.zhHans])),
    );
    const checkIns = week.members
      .flatMap(({ checkIns: each }) => each)
      .toSorted((a, b) => a.createdAt.getTime() - b.createdAt.getTime())
      .map((record): WeekCheckIn => ({
        id: record.id,
        member: record.member,
        day: record.day,
        createdAt: record.createdAt,
        kind: record.kind,
        ...entryOf(record, sportNames),
        reactions: week.reactions.get(record.id)?.length ?? 0,
        comments: (week.comments.get(record.id) ?? []).map(({ member, text }) => ({
          member,
          text,
        })),
      }));
    return {
      weekStart,
      members: week.members.map(({ member }) => {
        const nickname = squadmates.get(member)?.character?.nickname;
        return nickname === undefined ? { member } : { member, nickname };
      }),
      checkIns,
    };
  };
}

/** A check-in's sport, minutes and line, as the coach reads them. */
function entryOf(
  record: CheckInRecord,
  sportNames: ReadonlyMap<string, string>,
): Pick<WeekCheckIn, 'sport' | 'minutes' | 'text'> {
  switch (record.kind) {
    case 'trained': {
      const { sport, customSport, minutes, caption } = record.training;
      const name = customSport ?? sportNames.get(sport) ?? sport;
      return {
        sport: name,
        ...(minutes === undefined ? {} : { minutes }),
        ...(caption === undefined ? {} : { text: caption }),
      };
    }
    case 'healthyMeal':
    case 'cheatMeal':
      return record.meal.caption === undefined ? {} : { text: record.meal.caption };
    case 'disclaimer':
      return { text: record.disclaimer.text };
  }
}
