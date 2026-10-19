import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  AwardKind,
  LocalDay,
  MemberId,
  ReactionKind,
  SquadId,
  StatKind,
  WeekStart,
  type CheckIns,
} from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const count = (description: string) => z.int().min(0).meta({ description });

const Stat = z
  .strictObject({
    kind: StatKind.meta({
      description:
        '`trainedDays`: days with a 练了, several on one day counting once; `plannedDays`: ' +
        'training days in the weekly plan; `checkIns`: check-ins of every kind; ' +
        '`disclaimers`, `healthyMeals`, `cheatMeals`: check-ins of that kind; ' +
        '`reactionsReceived`: teammates’ reactions on them. A new kind is a contract change.',
    }),
    value: count('The count.'),
  })
  .openapi('WeekStat');

const Award = z
  .strictObject({
    kind: AwardKind.meta({
      description:
        '`planCompleted` (领奖台): everyone who trained at least as many days as they planned, ' +
        'and at least one, by their trained days. `crown` (皇冠): those on the podium with the ' +
        'most trained days, all of them on a tie. `bestDisclaimer` (本周最佳请假条): the 请假条 ' +
        'with the most reactions, at least one, the earliest posted on a tie, by its reactions. ' +
        'A new kind is a contract change.',
    }),
    winners: z
      .array(
        z.strictObject({
          member: z.uuid(),
          value: count('What they won it by, in the award’s own unit.'),
          checkIn: z
            .uuid()
            .optional()
            .meta({ description: 'The check-in that won it, for an award a check-in wins.' }),
        }),
      )
      .min(1)
      .meta({ description: 'Who won it, in the order members joined the squad.' }),
  })
  .openapi('WeekAward');

export const WeekSummaryBody = z
  .strictObject({
    version: bodyVersion(1),
    squad: z.uuid(),
    week: z.strictObject({ from: WeekStart, to: LocalDay }),
    final: z.boolean().meta({
      description:
        'Every member’s own Sunday is over: the week has been played and the card can show. ' +
        'Numbers can still move a little after that, from a check-in sent up to 48 hours late ' +
        'or a reaction left later. Before that the week is still being played.',
    }),
    awards: z.array(Award).meta({
      description: 'The awards someone won this week; one nobody won is left out.',
    }),
    squadTotals: z.strictObject({
      stats: z.array(Stat).meta({ description: 'Each count added up over the members.' }),
      reactions: z
        .array(z.strictObject({ kind: ReactionKind, count: count('Reactions of this kind.') }))
        .meta({ description: 'Teammates’ reactions on the week’s check-ins, one entry a kind.' }),
    }),
    me: z.strictObject({
      stats: z.array(Stat).meta({ description: 'The signed-in member’s own counts.' }),
      reactions: z
        .array(
          z.strictObject({
            kind: ReactionKind,
            received: count('Reactions of this kind on their check-ins.'),
            given: count('Reactions of this kind they left on teammates’ check-ins.'),
          }),
        )
        .meta({ description: 'One entry a reaction kind.' }),
    }),
  })
  .openapi('WeekSummary');

/** `GET /squads/{squadId}/weeks/{weekStart}/summary`: a squad's 周日战报 data. */
export function weekSummary(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
}) {
  const route = createRoute({
    method: 'get',
    path: '/squads/{squadId}/weeks/{weekStart}/summary',
    operationId: 'getSquadWeekSummary',
    summary: 'A squad’s week: its awards and counts (周日战报)',
    description:
      'From check-ins sent to the squad by everyone in it now, against their weekly plans. A ' +
      'week runs Monday to Sunday on each member’s own clock, where a day lasts until 3am. Only ' +
      'winners are named and only the signed-in member’s own counts are shown, so nobody is ' +
      'ranked last. Reactions count only from members of the squad now. Any week that has ' +
      'started can be read; until `final`, it is still being played. Only for members of the ' +
      'squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({
        squadId: SquadId,
        weekStart: WeekStart.meta({ description: 'The week’s Monday.', example: '2026-10-19' }),
      }),
    },
    responses: {
      200: {
        description: 'The week',
        content: { 'application/json': { schema: WeekSummaryBody } },
      },
      400: problem('Not a Monday, or a week that hasn’t started yet (`WEEK_NOT_STARTED`)'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The member isn’t in this squad'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const { squadId: squad, weekStart } = c.req.valid('param');
    const summary = await deps.checkIns.weekSummary({
      viewer: MemberId.parse(c.var.caller.userId),
      squad,
      weekStart,
    });
    return c.json(
      {
        version: 1 as const,
        squad,
        week: { from: summary.from, to: summary.to },
        final: summary.final,
        awards: summary.awards.map(({ kind, winners }) => ({
          kind,
          winners: winners.map(({ member, value, checkIn }) => ({
            member,
            value,
            ...(checkIn === undefined ? {} : { checkIn }),
          })),
        })),
        squadTotals: summary.squad,
        me: summary.me,
      },
      200,
    );
  });
}
