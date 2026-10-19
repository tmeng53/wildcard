import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { LocalDay, MemberId, SquadId, type CheckIns } from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const count = (description: string) => z.int().min(0).meta({ description });

const MemberToday = z.strictObject({
  member: z.uuid(),
  day: LocalDay.meta({
    description:
      'The member’s own today: their local date in their time zone, where anything before 3am ' +
      'still counts for the day before.',
  }),
  training: z.enum(['trained', 'disclaimer', 'notCheckedIn']).meta({
    description:
      'Where their today stands, from check-ins sent to this squad. A 练了 wins over a ' +
      '免责声明 posted earlier the same day.',
  }),
  latestMeal: z
    .enum(['healthyMeal', 'cheatMeal'])
    .optional()
    .meta({ description: 'Their latest meal today sent to this squad. Missing when none.' }),
});

export const SquadToday = z
  .strictObject({
    version: bodyVersion(1),
    squad: z.uuid(),
    members: z.array(MemberToday).meta({
      description: 'Everyone in the squad now, the signed-in member included, in join order.',
    }),
    today: z.strictObject({
      trained: count('Members whose today is trained.'),
      disclaimer: count('Members whose today is a 免责声明 with no 练了.'),
      everyoneTrained: z.boolean().meta({ description: 'Every member’s today is trained.' }),
    }),
    me: z.strictObject({
      week: z.strictObject({
        from: LocalDay,
        to: LocalDay,
        trainedDays: count(
          'Days this week with a 练了, wherever it was sent. Several on one day count once.',
        ),
      }),
      lifetimeTrainedDays: count('Days ever with a 练了.'),
    }),
    squadWeek: z.strictObject({
      trainedDays: count(
        'Days trained this week, added up over the members, each in their own week and from ' +
          'check-ins sent to this squad.',
      ),
    }),
  })
  .openapi('SquadToday');

/** `GET /squads/{squadId}/today`: the home screen's squad, for one of its members. */
export function squadToday(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
}) {
  const route = createRoute({
    method: 'get',
    path: '/squads/{squadId}/today',
    operationId: 'getSquadToday',
    summary: 'Where a squad’s day and week stand',
    description:
      'Each member’s today and this week’s counts, as the home screen shows them. Every member’s ' +
      'day and week are their own, in their time zone; weeks start on Monday. A member who hasn’t ' +
      'saved a profile yet is read on the signed-in member’s clock. Only for members of the squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ squadId: SquadId }) },
    responses: {
      200: {
        description: 'The squad’s day',
        content: { 'application/json': { schema: SquadToday } },
      },
      401: problem('No bearer token, or not a valid one'),
      403: problem('The member isn’t in this squad'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const squad = c.req.valid('param').squadId;
    const today = await deps.checkIns.squadToday({
      viewer: MemberId.parse(c.var.caller.userId),
      squad,
    });
    return c.json(
      {
        version: 1 as const,
        squad,
        members: today.members.map(({ latestMeal, ...member }) =>
          latestMeal === undefined ? member : { ...member, latestMeal },
        ),
        today: {
          trained: today.trainedToday,
          disclaimer: today.disclaimerToday,
          everyoneTrained: today.everyoneTrained,
        },
        me: {
          week: {
            from: today.myWeek.from,
            to: today.myWeek.to,
            trainedDays: today.myWeek.trainedDays,
          },
          lifetimeTrainedDays: today.myLifetimeTrainedDays,
        },
        squadWeek: { trainedDays: today.squadTrainedDays },
      },
      200,
    );
  });
}
