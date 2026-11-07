import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, SquadId, type SquadTimeZone, type Squads } from '@wildcard/squads';
import { TimeZone } from '@wildcard/time-zones';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

export const squadTimeZoneField = TimeZone.meta({
  description:
    'The squad’s time zone (小队时区), an IANA name: the clock of what the whole squad shares, ' +
    'its 战报 and awards freezing Sunday 8pm and its coach’s daily 战术板. Each member’s own day, ' +
    '6pm push and coach’s note keep their own profile’s zone.',
  example: 'Asia/Taipei',
});

const SquadTimeZoneBody = z
  .strictObject({
    version: bodyVersion(1),
    timeZone: squadTimeZoneField.meta({ description: 'This week’s zone.' }),
    nextTimeZone: squadTimeZoneField.meta({
      description:
        'Next week’s zone: a change counts from the next week, so it differs from `timeZone` ' +
        'only after the captain changed it this week.',
    }),
    canChange: z.boolean().meta({ description: 'True for the captain, the only one who sets it.' }),
  })
  .openapi('SquadTimeZone');

const SquadTimeZoneChange = z
  .strictObject({ version: bodyVersion(1), timeZone: squadTimeZoneField })
  .openapi('SquadTimeZoneChange');

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET` and `PUT /squads/{squadId}/time-zone`: the squad's time zone (小队时区), in the squad's
 * week on its own clock.
 */
export function squadTimeZone(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
}) {
  const params = z.strictObject({ squadId: SquadId });
  const zoneResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: SquadTimeZoneBody } },
  });

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/time-zone',
    operationId: 'getSquadTimeZone',
    summary: 'The squad’s time zone',
    description: 'For its members, in the squad’s week on its own clock.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: zoneResponse('The zone'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const change = createRoute({
    method: 'put',
    path: '/squads/{squadId}/time-zone',
    operationId: 'setSquadTimeZone',
    summary: 'Set the squad’s time zone',
    description:
      'For the captain. It counts from the squad’s next week on its own clock, so a week’s 战报 never moves ' +
      'while the squad plays it. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: SquadTimeZoneChange } } },
    },
    responses: {
      200: zoneResponse('The zone, with next week’s changed'),
      400: problem('Not a valid squad id, or a zone that doesn’t exist (`TIME_ZONE_UNKNOWN`)'),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
          '(`NOT_SQUAD_CAPTAIN`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  async function body(input: {
    readonly squad: SquadId;
    readonly viewer: MemberId;
    readonly zone: SquadTimeZone;
  }): Promise<z.infer<typeof SquadTimeZoneBody>> {
    const found = await deps.squads.find({ squad: input.squad, viewer: input.viewer });
    return {
      version: 1,
      timeZone: input.zone.timeZone,
      nextTimeZone: input.zone.nextTimeZone,
      canChange: found.captain === input.viewer,
    };
  }

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      const viewer = MemberId.parse(c.var.caller.userId);
      const zone = await deps.squads.timeZone({ squad: squadId, viewer, moment: new Date() });
      return c.json(await body({ squad: squadId, viewer, zone }), 200);
    })
    .openapi(change, async (c) => {
      const { squadId } = c.req.valid('param');
      const member = MemberId.parse(c.var.caller.userId);
      const zone = await deps.squads.setTimeZone({
        squad: squadId,
        member,
        timeZone: c.req.valid('json').timeZone,
        moment: new Date(),
      });
      return c.json(await body({ squad: squadId, viewer: member, zone }), 200);
    });
}
