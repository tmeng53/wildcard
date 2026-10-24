import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, TITLE_MAX, type WeeklyAwards } from '@wildcard/weekly-awards';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const AwardTotals = z
  .strictObject({
    version: bodyVersion(1),
    titles: z.int().nonnegative().meta({
      description: 'Every title (周奖) the member has won, in all their squads and weeks.',
      example: 3,
    }),
    latest: z
      .strictObject({
        title: z
          .string()
          .min(1)
          .meta({
            description: `The title, at most ${String(TITLE_MAX)} characters.`,
            example: '早八战神',
          }),
        times: z.int().positive().meta({
          description: 'How many times the member has won this title.',
          example: 2,
        }),
      })
      .optional()
      .meta({ description: 'The latest title they won. Left out before the first.' })
      .openapi('LatestTitle'),
  })
  .openapi('AwardTotals');

/** `GET /me/award-totals`: the weekly titles the signed-in member has won, for their player card. */
export function awardTotals(deps: {
  readonly verifyToken: VerifyToken;
  readonly awards: WeeklyAwards;
}) {
  const route = createRoute({
    method: 'get',
    path: '/me/award-totals',
    operationId: 'getMyAwardTotals',
    summary: 'The weekly titles the signed-in member has won',
    description:
      'Every title from the Sunday 战报’s awards (本周颁奖) in all their squads, for 周奖 on ' +
      'their player card in 我. Counts only go up, until a squad is deleted.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: { description: 'The titles', content: { 'application/json': { schema: AwardTotals } } },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const won = await deps.awards.titlesWon(MemberId.parse(c.var.caller.userId));
    return c.json(
      {
        version: 1 as const,
        titles: won.count,
        ...(won.latest === undefined ? {} : { latest: won.latest }),
      },
      200,
    );
  });
}
