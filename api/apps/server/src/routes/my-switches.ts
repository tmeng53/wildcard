import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { SwitchId, type Switches } from '@wildcard/switches';

import { bodyVersion } from '../body-version.js';
import { newYorkDay } from '../new-york-day.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const MySwitches = z
  .strictObject({
    version: bodyVersion(1),
    on: z.array(SwitchId).meta({
      description:
        'The global switches on for the signed-in member today, by id: what the public catalog’s ' +
        '`switches` say, plus, for a member who previews switches, those in preview, on the day ' +
        'they pretend it is. A signed-in app follows this list over the catalog’s.',
      example: ['winter'],
    }),
  })
  .openapi('MySwitches');

/** `GET /me/switches`: which global switches are on for the signed-in member today. */
export function mySwitches(deps: {
  readonly verifyToken: VerifyToken;
  readonly switches: Pick<Switches, 'list' | 'statesFor'>;
  readonly clock: () => Date;
}) {
  const route = createRoute({
    method: 'get',
    path: '/me/switches',
    operationId: 'getMySwitches',
    summary: 'The global switches on for the signed-in member today',
    description:
      'Limited stores and scenes follow global switches. Most members see them as the public ' +
      'catalog says; a member who previews switches (an admin trying an event before it goes ' +
      'live) also sees those in preview, on the day they pretend it is.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'The switches on',
        content: { 'application/json': { schema: MySwitches } },
      },
      401: problem('No bearer token, or not a valid one'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const [all, { on }] = await Promise.all([
      deps.switches.list(),
      deps.switches.statesFor(c.var.caller.userId),
    ]);
    const today = newYorkDay(deps.clock());
    return c.json(
      { version: 1 as const, on: all.map(({ id }) => id).filter((id) => on(id, today)) },
      200,
    );
  });
}
