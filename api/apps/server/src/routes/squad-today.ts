import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { LocalDay, MemberId, SquadId, type CheckIns } from '@wildcard/check-ins';
import type { Members } from '@wildcard/members';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const count = (description: string) => z.int().min(0).meta({ description });

const MemberToday = z.strictObject({
  member: z.uuid(),
  catchphrase: z
    .string()
    .nullable()
    .meta({
      description:
        'What the member’s character shouts when the squad cheers a teammate’s 练了 (口头禅). ' +
        'Null when they haven’t picked one: the app uses their persona’s own line.',
    }),
  day: LocalDay.meta({
    description:
      'The member’s own today: their local date in their time zone, where anything before 3am ' +
      'still counts for the day before.',
  }),
  training: z.enum(['trained', 'disclaimer', 'notCheckedIn']).meta({
    description:
      'Where their today stands, from check-ins sent to this squad. A 练了 wins over a ' +
      '请假条 posted earlier the same day.',
  }),
  latestMeal: z
    .enum(['healthyMeal', 'cheatMeal'])
    .optional()
    .meta({ description: 'Their latest meal today sent to this squad. Missing when none.' }),
  plannedRest: z
    .boolean()
    .meta({ description: 'Today is a rest day in their weekly plan, whatever they checked in.' }),
  firstCheckInAt: z.iso
    .datetime()
    .optional()
    .meta({
      description:
        'When their first check-in today sent to this squad was made, of any kind, in UTC. Missing ' +
        'when none.',
    }),
});

export const SquadToday = z
  .strictObject({
    version: bodyVersion(1),
    squad: z.uuid(),
    members: z.array(MemberToday).meta({
      description:
        'Everyone in the squad now, the signed-in member included, in the home screen’s order: ' +
        'first those who checked in today, by their first check-in; then those on a planned ' +
        'rest day; then everyone else. Ties keep the order members joined.',
    }),
    today: z.strictObject({
      trained: count('Members whose today is trained.'),
      disclaimer: count('Members whose today is a 请假条 with no 练了.'),
      resting: count('Members on a planned rest day with no 练了 or 请假条 today.'),
      everyoneTrained: z.boolean().meta({
        description:
          'At least one member trained today and every member who did not train is on a planned rest day, ' +
          'whatever they checked in (全员上场).',
      }),
    }),
    me: z.strictObject({
      week: z.strictObject({
        from: LocalDay,
        to: LocalDay,
        trainedDays: count(
          'Days this week with a 练了, wherever it was sent. Several on one day count once.',
        ),
        plannedDays: count('Training days in this week’s plan: the y in 本周 x/y.'),
      }),
      lifetimeTrainedDays: count('Days ever with a 练了.'),
    }),
    squadWeek: z.strictObject({
      trainedDays: count(
        'Days trained this week, added up over the members, each in their own week and from ' +
          'check-ins sent to this squad.',
      ),
      plannedDays: count(
        'Training days planned this week, added up over the members’ plans, each in their own week.',
      ),
    }),
  })
  .openapi('SquadToday');

/** `GET /squads/{squadId}/today`: the home screen's squad, for one of its members. */
export function squadToday(deps: {
  readonly verifyToken: VerifyToken;
  readonly checkIns: CheckIns;
  readonly members: Members;
}) {
  const route = createRoute({
    method: 'get',
    path: '/squads/{squadId}/today',
    operationId: 'getSquadToday',
    summary: 'Where a squad’s day and week stand',
    description:
      'Each member’s today and this week’s counts, as the home screen shows them. Every member’s ' +
      'day and week are their own, in their time zone; weeks start on Monday, and a member who ' +
      'hasn’t saved a weekly plan has the default one. A member who hasn’t ' +
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
    // Only after squadToday, which refuses a viewer outside the squad.
    const catchphrases = await deps.members.catchphrasesOf(
      today.members.map(({ member }) => member),
    );
    return c.json(
      {
        version: 1 as const,
        squad,
        members: today.members.map(({ latestMeal, firstCheckInAt, ...member }) => ({
          ...member,
          catchphrase: catchphrases.get(member.member) ?? null,
          ...(latestMeal === undefined ? {} : { latestMeal }),
          ...(firstCheckInAt === undefined ? {} : { firstCheckInAt: firstCheckInAt.toISOString() }),
        })),
        today: {
          trained: today.trainedToday,
          disclaimer: today.disclaimerToday,
          resting: today.restingToday,
          everyoneTrained: today.everyoneTrained,
        },
        me: {
          week: {
            from: today.myWeek.from,
            to: today.myWeek.to,
            trainedDays: today.myWeek.trainedDays,
            plannedDays: today.myWeek.plannedDays,
          },
          lifetimeTrainedDays: today.myLifetimeTrainedDays,
        },
        squadWeek: today.squadWeek,
      },
      200,
    );
  });
}
