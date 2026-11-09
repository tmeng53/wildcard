import type { SceneWeek } from '../../domain/scene.js';
import type { MemberId, SquadId } from '../../domain/squad.js';
import { goalFor, weekAfter, type DaysPerMember } from '../../domain/weekly-goal.js';
import { NotSquadCaptainError } from '../../errors.js';
import type { SquadStore } from '../../ports.js';
import { findSquad } from './find-squad.js';

/** A squad's weekly goal (人均 N 次) this week and next, as its members see it. */
export interface WeeklyGoal {
  /** This week's goal. */
  readonly daysPerMember: DaysPerMember;
  /** Next week's: a captain's change counts from the next week. */
  readonly nextDaysPerMember: DaysPerMember;
}

interface Deps {
  readonly store: SquadStore;
}

/** The squad's weekly goal in the viewer's week (its Monday) and the week after. */
export async function weeklyGoal(
  deps: Deps,
  input: { readonly squad: SquadId; readonly viewer: MemberId; readonly week: SceneWeek },
): Promise<WeeklyGoal> {
  await findSquad(deps, { squad: input.squad, viewer: input.viewer });
  const settings = await deps.store.weeklyGoals(input.squad);
  return {
    daysPerMember: goalFor(settings, input.week),
    nextDaysPerMember: goalFor(settings, weekAfter(input.week)),
  };
}

/**
 * Sets the squad's weekly goal, for its captain. It counts from the week after the captain's
 * week now, so a week's goal never moves while the squad trains towards it. Saving the goal
 * next week has already changes nothing.
 */
export async function setWeeklyGoal(
  deps: Deps,
  input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly daysPerMember: DaysPerMember;
    readonly week: SceneWeek;
  },
): Promise<WeeklyGoal> {
  await findSquad(deps, { squad: input.squad, viewer: input.member });
  const outcome = await deps.store.setWeeklyGoal({
    squad: input.squad,
    actor: input.member,
    daysPerMember: input.daysPerMember,
    week: weekAfter(input.week),
  });
  if (outcome === 'notCaptain') throw new NotSquadCaptainError();
  return weeklyGoal(deps, { squad: input.squad, viewer: input.member, week: input.week });
}
