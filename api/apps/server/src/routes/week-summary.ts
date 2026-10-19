import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { LocalDay, MemberId, SquadId, WeekStart, type CheckIns } from '@wildcard/check-ins';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';
import { AWARD_COPY, languageOf, REACTION_COPY, STAT_COPY } from './week-summary-copy.js';

const count = (description: string) => z.int().min(0).meta({ description });

/** A kind the app may not know yet; it shows the words that come with it either way. */
const openKind = (description: string) =>
  z
    .string()
    .min(1)
    .meta({
      description: `${description} New kinds come without an app release, so show any kind from its words.`,
    });

const words = (description: string) => z.string().min(1).meta({ description });

const Stat = z
  .strictObject({
    kind: openKind(
      'Today `trainedDays`, `plannedDays`, `checkIns`, `disclaimers`, `healthyMeals`, `cheatMeals` ' +
        'and `reactionsReceived`.',
    ),
    label: words('Its name, in the language asked for.'),
    value: count('The count.'),
  })
  .openapi('WeekStat');

const Award = z
  .strictObject({
    kind: openKind(
      'Today `planCompleted` (领奖台: trained at least as many days as planned, and at least one), ' +
        '`crown` (皇冠: the most days on the podium, all of them on a tie) and `bestDisclaimer` ' +
        '(本周最佳请假条: the most reactions, at least one, the earliest on a tie).',
    ),
    title: words('Its name, in the language asked for.'),
    symbol: z.string().min(1).meta({
      description: 'An SF Symbol name to show with it; fall back to a plain one if it is unknown.',
      example: 'crown.fill',
    }),
    winners: z
      .array(
        z.strictObject({
          member: z.uuid(),
          value: count('What they won it by, in the award’s own unit.'),
          text: words('What they won it by, in words, in the language asked for.'),
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

const reaction = {
  kind: openKind('Today `cheer` (加油), `highlight` (名场面) and `lol` (笑死).'),
  label: words('Its name, in the language asked for.'),
};

export const WeekSummaryBody = z
  .strictObject({
    version: bodyVersion(1),
    language: z.enum(['zh-Hans', 'en']).meta({ description: 'The language the words are in.' }),
    squad: z.uuid(),
    week: z.strictObject({ from: WeekStart, to: LocalDay }),
    final: z.boolean().meta({
      description:
        'Every member’s own Sunday is over: the week has been played and the card can show. ' +
        'Numbers can still change after that: a check-in sent up to 48 hours late, a reaction ' +
        'left, changed or taken off later, or a member joining or leaving, since the week is ' +
        'read for the squad as it is now. Before that the week is still being played.',
    }),
    awards: z.array(Award).meta({
      description: 'The awards someone won this week; one nobody won is left out.',
    }),
    squadTotals: z.strictObject({
      stats: z.array(Stat).meta({ description: 'Each count added up over the members.' }),
      reactions: z
        .array(z.strictObject({ ...reaction, count: count('Reactions of this kind.') }))
        .meta({ description: 'Teammates’ reactions on the week’s check-ins, one entry a kind.' }),
    }),
    me: z.strictObject({
      stats: z.array(Stat).meta({ description: 'The signed-in member’s own counts.' }),
      reactions: z
        .array(
          z.strictObject({
            ...reaction,
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
      headers: z.object({
        'accept-language': z.string().optional().meta({
          description: 'The language to write the words in: Chinese (the default) or English.',
          example: 'zh-Hans',
        }),
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
    const language = languageOf(c.req.valid('header')['accept-language']);
    const summary = await deps.checkIns.weekSummary({
      viewer: MemberId.parse(c.var.caller.userId),
      squad,
      weekStart,
    });
    const statsOf = (stats: typeof summary.me.stats) =>
      stats.map(({ kind, value }) => ({ kind, label: STAT_COPY[kind][language], value }));
    return c.json(
      {
        version: 1 as const,
        language,
        squad,
        week: { from: summary.from, to: summary.to },
        final: summary.final,
        awards: summary.awards.map(({ kind, winners }) => ({
          kind,
          title: AWARD_COPY[kind].title[language],
          symbol: AWARD_COPY[kind].symbol,
          winners: winners.map(({ member, value, checkIn }) => ({
            member,
            value,
            text: AWARD_COPY[kind].winner(value)[language],
            ...(checkIn === undefined ? {} : { checkIn }),
          })),
        })),
        squadTotals: {
          stats: statsOf(summary.squad.stats),
          reactions: summary.squad.reactions.map(({ kind, count: total }) => ({
            kind,
            label: REACTION_COPY[kind][language],
            count: total,
          })),
        },
        me: {
          stats: statsOf(summary.me.stats),
          reactions: summary.me.reactions.map(({ kind, received, given }) => ({
            kind,
            label: REACTION_COPY[kind][language],
            received,
            given,
          })),
        },
      },
      200,
    );
  });
}
