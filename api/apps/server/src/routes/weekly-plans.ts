import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  MemberId,
  PlanDays,
  WeekStart,
  type WeeklyPlan,
  type WeeklyPlans,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const days = PlanDays.meta({
  description:
    'Seven days, Monday first: `{"kind": "train"}`, optionally with a `sport` (and ' +
    '`customSport` for `"custom"`), or `{"kind": "rest"}`.',
});

/** A member's plan for one week, as the app's contract has it (`WeeklyPlan` in ios/Packages/Contracts). */
export const WeeklyPlanBody = z
  .strictObject({
    version: bodyVersion(1),
    member: z.uuid().meta({ description: 'The member whose plan it is.' }),
    weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
    days,
    source: z.enum(['saved', 'carriedOver', 'default']).meta({
      description:
        '`saved` for a plan saved for this week; `carriedOver` when the week follows the ' +
        'member’s latest earlier plan; `default` (rest on Wednesday and Sunday) before their ' +
        'first save.',
    }),
  })
  .openapi('WeeklyPlan');

const WeeklyPlanDraft = z
  .strictObject({ version: bodyVersion(1), days })
  .openapi('WeeklyPlanDraft');

const wire = (member: string, plan: WeeklyPlan) => ({ version: 1 as const, member, ...plan });

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

const params = z.strictObject({
  weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
});

/** `GET` and `PUT /me/weekly-plans/{weekStart}`: the signed-in member's plan for a week. */
export function weeklyPlans(deps: {
  readonly verifyToken: VerifyToken;
  readonly weeklyPlans: WeeklyPlans;
}) {
  const get = createRoute({
    method: 'get',
    path: '/me/weekly-plans/{weekStart}',
    operationId: 'getMyWeeklyPlan',
    summary: 'The signed-in member’s plan for a week',
    description:
      'Every week has a plan: the one saved for it, else the member’s latest earlier one, ' +
      'else the default.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: { description: 'The plan', content: { 'application/json': { schema: WeeklyPlanBody } } },
      400: problem('Not a Monday'),
      ...signedInFailures,
    },
  });

  const put = createRoute({
    method: 'put',
    path: '/me/weekly-plans/{weekStart}',
    operationId: 'saveMyWeeklyPlan',
    summary: 'Save the signed-in member’s plan for a week',
    description:
      'Replaces the week’s plan; repeating a save gives the same result. Past weeks are ' +
      'read-only, later weeks change freely, and a member plans up to 4 weeks ahead. In the ' +
      'current week, from the day the member joined: days before today stay as they were, ' +
      'today stays a training or a rest day (its sport may change), and the number of rest ' +
      'days is fixed. On the day a member joins, a week still on the default changes freely. ' +
      'Days are read in the member’s profile time zone, and a day lasts until 3am.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: WeeklyPlanDraft } } },
    },
    responses: {
      200: { description: 'Saved', content: { 'application/json': { schema: WeeklyPlanBody } } },
      400: problem(
        'Not a valid plan or not a Monday; a week that is over (`WEEK_OVER`) or too far ahead ' +
          '(`WEEK_TOO_FAR_AHEAD`); a change to a day that has started (`PLAN_DAY_STARTED`) or ' +
          'to this week’s number of rest days (`REST_DAYS_FIXED`); or no profile yet ' +
          '(`TIME_ZONE_NOT_SET`)',
      ),
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(get, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const plan = await deps.weeklyPlans.find({
        member,
        weekStart: c.req.valid('param').weekStart,
      });
      return c.json(wire(member, plan), 200);
    })
    .openapi(put, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const plan = await deps.weeklyPlans.save({
        member,
        weekStart: c.req.valid('param').weekStart,
        days: c.req.valid('json').days,
      });
      return c.json(wire(member, plan), 200);
    });
}
