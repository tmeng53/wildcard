import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { WeekStart, type CheckIns } from '@wildcard/check-ins';
import { DaysPerMember, MemberId, SquadId, type Squads, type WeeklyGoal } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** How many finished weeks the recent average looks back over, at most. */
export const RECENT_WEEKS = 4;

const DAY = 86_400_000;

const daysPerMemberField = DaysPerMember.meta({
  description:
    'How many times each member trains a week on average (人均 N 次), 1 to 7. The squad’s goal ' +
    'for a week is this times its members; anyone’s 训练 sent to the squad count towards it, ' +
    'several on one day each counting.',
  example: 3,
});

const SquadWeeklyGoalBody = z
  .strictObject({
    version: bodyVersion(1),
    daysPerMember: daysPerMemberField.meta({ description: 'This week’s goal (人均 N 次).' }),
    nextDaysPerMember: daysPerMemberField.meta({
      description:
        'Next week’s goal: a change counts from the next week, so it differs from ' +
        '`daysPerMember` only after the captain changed it this week.',
    }),
    canChange: z.boolean().meta({ description: 'True for the captain, the only one who sets it.' }),
    recent: z
      .strictObject({
        weeks: z
          .int()
          .min(1)
          .max(RECENT_WEEKS)
          .meta({
            description: `How many finished weeks it averages: up to ${String(RECENT_WEEKS)}.`,
          }),
        daysPerMember: z
          .number()
          .min(0)
          .max(7)
          .meta({
            description:
              'The 训练 each member sent to the squad on average in those weeks, to one ' +
              'decimal: each week’s 训练 over its members then, at most 7 (人均 N 次 goes no ' +
              'higher). The name is from when it counted days.',
            example: 3.4,
          }),
      })
      .nullable()
      .meta({ description: 'Null until the squad has a finished week.' }),
  })
  .openapi('SquadWeeklyGoal');

const SquadWeeklyGoalChange = z
  .strictObject({ version: bodyVersion(1), daysPerMember: daysPerMemberField })
  .openapi('SquadWeeklyGoalChange');

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** The Monday `weeks` weeks before `week`. */
function weeksBefore(week: WeekStart, weeks: number): WeekStart {
  return WeekStart.parse(new Date(Date.parse(week) - weeks * 7 * DAY).toISOString().slice(0, 10));
}

/**
 * `GET` and `PUT /squads/{squadId}/weekly-goal`: the squad's weekly goal (小队每周目标, 人均 N 次)
 * and how the squad did lately (小队页's 每周目标). It spans modules: the squads keep the goal
 * and who was in the squad when, the check-ins count the 训练 sent to the squad in each
 * member's week.
 */
export function squadWeeklyGoal(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly checkIns: Pick<CheckIns, 'weekStartNow' | 'squadTrainings'>;
}) {
  const params = z.strictObject({ squadId: SquadId });
  const goalResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: SquadWeeklyGoalBody } },
  });

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/weekly-goal',
    operationId: 'getSquadWeeklyGoal',
    summary: 'The squad’s weekly goal and its recent average',
    description: 'For its members, in the caller’s week.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: goalResponse('The goal'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const change = createRoute({
    method: 'put',
    path: '/squads/{squadId}/weekly-goal',
    operationId: 'setSquadWeeklyGoal',
    summary: 'Set the squad’s weekly goal',
    description:
      'For the captain. It counts from next week (the captain’s), so a week’s goal never moves ' +
      'while the squad trains towards it. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: SquadWeeklyGoalChange } } },
    },
    responses: {
      200: goalResponse('The goal, with next week’s changed'),
      400: problem('Not a valid squad id or goal'),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
          '(`NOT_SQUAD_CAPTAIN`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  /**
   * The times each member trained on average over the squad's latest finished weeks, up to
   * `RECENT_WEEKS`, from the week it was made on; undefined before its first week ends.
   */
  async function recentOf(
    squad: SquadId,
    since: { readonly week: WeekStart; readonly createdAt: Date },
  ) {
    const { week, createdAt } = since;
    const averages: number[] = [];
    for (let back = 1; back <= RECENT_WEEKS; back += 1) {
      const weekStart = weeksBefore(week, back);
      const end = new Date(Date.parse(weeksBefore(week, back - 1)));
      // A week that ended before the squad was made isn't one of its weeks.
      if (end <= createdAt) break;
      const members = await deps.squads.membersAt(squad, end);
      if (members.length === 0) continue;
      const trained = await deps.checkIns.squadTrainings({ squad, members, weekStart });
      averages.push(trained / members.length);
    }
    if (averages.length === 0) return null;
    const mean = averages.reduce((sum, each) => sum + each, 0) / averages.length;
    // Several 训练 a day can pass 7 a member; the goal goes no higher, so neither does this.
    return { weeks: averages.length, daysPerMember: Math.min(7, Math.round(mean * 10) / 10) };
  }

  async function body(input: {
    readonly squad: SquadId;
    readonly viewer: MemberId;
    readonly week: WeekStart;
    readonly goal: WeeklyGoal;
  }): Promise<z.infer<typeof SquadWeeklyGoalBody>> {
    const { squad, viewer, week, goal } = input;
    const found = await deps.squads.find({ squad, viewer });
    return {
      version: 1,
      daysPerMember: goal.daysPerMember,
      nextDaysPerMember: goal.nextDaysPerMember,
      canChange: found.captain === viewer,
      recent: await recentOf(squad, { week, createdAt: found.createdAt }),
    };
  }

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      const viewer = MemberId.parse(c.var.caller.userId);
      const week = await deps.checkIns.weekStartNow(viewer);
      const goal = await deps.squads.weeklyGoal({ squad: squadId, viewer, week });
      return c.json(await body({ squad: squadId, viewer, week, goal }), 200);
    })
    .openapi(change, async (c) => {
      const { squadId } = c.req.valid('param');
      const member = MemberId.parse(c.var.caller.userId);
      const week = await deps.checkIns.weekStartNow(member);
      const goal = await deps.squads.setWeeklyGoal({
        squad: squadId,
        member,
        daysPerMember: c.req.valid('json').daysPerMember,
        week,
      });
      return c.json(await body({ squad: squadId, viewer: member, week, goal }), 200);
    });
}
