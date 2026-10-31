import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  FuelGoals,
  MemberId,
  PlanDays,
  WeekStart,
  type PlannedWeek,
  type WeeklyPlans,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const days = PlanDays.meta({
  id: 'PlanDays',
  description:
    'Seven days, Monday first: `{"kind": "train"}`, optionally with a `sport` (and ' +
    '`customSport` for `"custom"`), or `{"kind": "rest"}`.',
});

const fuelGoals = FuelGoals.meta({
  id: 'FuelGoals',
  description:
    'The week’s 饮食小目标, at most 3 in the order picked, each once: ' +
    '`{"kind": "suggested", "suggestion": "water"}` for one the app suggests, or ' +
    '`{"kind": "own", "text": "少喝冰美式"}` in the member’s own words (1 to 8 characters, one ' +
    'line). Only those saved for this week; goals don’t carry over.',
});

/** A member's plan for one week, as the app's contract has it (`WeeklyPlan` in ios/Packages/Contracts). */
export const WeeklyPlanBody = z
  .strictObject({
    version: bodyVersion(1),
    member: z.uuid().meta({ description: 'The member whose plan it is.' }),
    weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
    days,
    // Builds already installed decode this strictly, so a week following the typical week keeps
    // the name it had when such a week followed an earlier one.
    source: z.enum(['saved', 'carriedOver', 'default']).meta({
      description:
        '`saved` for a plan saved for this week; `carriedOver` when the week follows the ' +
        'member’s typical week (`/me/plan-template`); `default` (rest on Wednesday and Sunday) ' +
        'before they make one.',
    }),
    fuelGoals,
    firstWeek: WeekStart.optional().meta({
      description:
        'The Monday of the week the member joined, in their time zone: the earliest week the ' +
        '出赛表 looks back on. Missing before they save a profile.',
      example: '2026-10-12',
    }),
  })
  .openapi('WeeklyPlan');

const WeeklyPlanDraft = z
  .strictObject({ version: bodyVersion(1), days })
  .openapi('WeeklyPlanDraft');

/** The member's typical week (每周模板), which each week follows until it is changed for itself. */
const PlanTemplateBody = z
  .strictObject({
    version: bodyVersion(1),
    days,
    source: z.enum(['saved', 'default']).meta({
      description:
        '`saved` for the member’s own; `default` (rest on Wednesday and Sunday) before they ' +
        'make one.',
    }),
  })
  .openapi('PlanTemplate');

const PlanTemplateDraft = z
  .strictObject({ version: bodyVersion(1), days })
  .openapi('PlanTemplateDraft');

const FuelGoalsDraft = z
  .strictObject({ version: bodyVersion(1), goals: fuelGoals })
  .openapi('FuelGoalsDraft');

const wire = (member: string, { firstWeek, source, ...week }: PlannedWeek) => ({
  version: 1 as const,
  member,
  ...week,
  source: source === 'template' ? ('carriedOver' as const) : source,
  ...(firstWeek === undefined ? {} : { firstWeek }),
});

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

const params = z.strictObject({
  weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
});

/**
 * `GET` and `PUT /me/weekly-plans/{weekStart}`: the signed-in member's plan for a week,
 * `PUT …/fuel-goals`: its 饮食小目标, and `GET` and `PUT /me/plan-template`: their typical week.
 */
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
      'Every week has a plan: the one saved for it, else the member’s typical week as it ' +
      'stood when the week began, else the default.',
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
      'a training today stays a training day (its sport may change), a rest today may ' +
      'become one, and later days change freely. On the day a member joins, a week still on ' +
      'the default changes freely. Days are read in the member’s profile time zone, and a ' +
      'day lasts until 3am.',
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
          '(`WEEK_TOO_FAR_AHEAD`); a change to a day that has started (`PLAN_DAY_STARTED`); or ' +
          'no profile yet (`TIME_ZONE_NOT_SET`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const putFuelGoals = createRoute({
    method: 'put',
    path: '/me/weekly-plans/{weekStart}/fuel-goals',
    operationId: 'saveMyFuelGoals',
    summary: 'Set the signed-in member’s 饮食小目标 for a week',
    description:
      'Replaces the week’s goals; repeating a save gives the same result. For this week on the ' +
      'member’s clock or a later one, up to 4 weeks ahead. Answers with the whole week.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: FuelGoalsDraft } } },
    },
    responses: {
      200: { description: 'Saved', content: { 'application/json': { schema: WeeklyPlanBody } } },
      400: problem(
        'Not valid goals or not a Monday; a week that is over (`WEEK_OVER`) or too far ahead ' +
          '(`WEEK_TOO_FAR_AHEAD`); or no profile yet (`TIME_ZONE_NOT_SET`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const getTemplate = createRoute({
    method: 'get',
    path: '/me/plan-template',
    operationId: 'getMyPlanTemplate',
    summary: 'The signed-in member’s typical week',
    description: 'The plan the weeks to come follow until one is changed for itself.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The typical week',
        content: { 'application/json': { schema: PlanTemplateBody } },
      },
      ...signedInFailures,
    },
  });

  const putTemplate = createRoute({
    method: 'put',
    path: '/me/plan-template',
    operationId: 'saveMyPlanTemplate',
    summary: 'Save the signed-in member’s typical week',
    description:
      'Replaces the typical week; repeating a save gives the same result. Saved on the day the ' +
      'member joined, it is that week’s plan too; a change on a later day applies from next ' +
      'week, so this week keeps its plan. Weeks saved for themselves keep theirs.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: PlanTemplateDraft } } },
    },
    responses: {
      200: {
        description: 'Saved',
        content: { 'application/json': { schema: PlanTemplateBody } },
      },
      400: problem(
        'Not a valid plan, a sport the list doesn’t have (`SPORT_NOT_LISTED`), or no profile ' +
          'yet (`TIME_ZONE_NOT_SET`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(getTemplate, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      return c.json({ version: 1 as const, ...(await deps.weeklyPlans.template({ member })) }, 200);
    })
    .openapi(putTemplate, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const template = await deps.weeklyPlans.saveTemplate({
        member,
        days: c.req.valid('json').days,
      });
      return c.json({ version: 1 as const, ...template }, 200);
    })
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
    })
    .openapi(putFuelGoals, async (c) => {
      const member = MemberId.parse(c.var.caller.userId);
      const week = await deps.weeklyPlans.saveFuelGoals({
        member,
        weekStart: c.req.valid('param').weekStart,
        goals: c.req.valid('json').goals,
      });
      return c.json(wire(member, week), 200);
    });
}
