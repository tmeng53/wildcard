import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, NudgeKind, SquadId, type Nudges } from '@wildcard/nudges';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const fields = {
  to: z.uuid().meta({ description: 'The squadmate to nudge.' }),
  kind: NudgeKind.meta({
    description:
      '催你练 (`train`) or 好好休息 (`rest`). The app shows each with its own copy: only ' +
      '`train` asks someone to work out.',
  }),
};

export const NudgeDraft = z
  .strictObject({ version: bodyVersion(1), ...fields })
  .openapi('NudgeDraft');
export const Nudge = z.strictObject({ version: bodyVersion(1), ...fields }).openapi('Nudge');

/**
 * Squadmates nudging each other: `POST /squads/{squadId}/nudges`. A nudge isn't pushed on its
 * own; the receiver's 6pm daily push counts it and names who sent it.
 */
export function nudges(deps: { readonly verifyToken: VerifyToken; readonly nudges: Nudges }) {
  const send = createRoute({
    method: 'post',
    path: '/squads/{squadId}/nudges',
    operationId: 'nudgeSquadmate',
    summary: 'Nudge a squadmate: 催你练 or 好好休息',
    description:
      'At most one of each kind a day (on the caller’s clock) to each squadmate: the same ' +
      'nudge again the same day changes nothing, so it is safe to repeat. Not pushed at once: ' +
      'the squadmate’s 6pm daily push names who nudged them.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId }),
      body: { required: true, content: { 'application/json': { schema: NudgeDraft } } },
    },
    responses: {
      200: {
        description: 'Sent already today',
        content: { 'application/json': { schema: Nudge } },
      },
      201: { description: 'Sent', content: { 'application/json': { schema: Nudge } } },
      400: problem('Not a valid nudge, or to the caller themselves (`OWN_NUDGE`)'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      404: problem('The squadmate isn’t in this squad (`NOT_A_SQUADMATE`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(send, async (c) => {
    const { to, kind } = c.req.valid('json');
    const outcome = await deps.nudges.send({
      from: MemberId.parse(c.var.caller.userId),
      to: MemberId.parse(to),
      squad: c.req.valid('param').squadId,
      kind,
    });
    const body = { version: 1 as const, to, kind };
    return outcome === 'created' ? c.json(body, 201) : c.json(body, 200);
  });
}
