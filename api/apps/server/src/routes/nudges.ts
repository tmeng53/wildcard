import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { MemberId, NudgeKind, SquadId, type Nudges } from '@wildcard/nudges';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const fields = {
  to: z.uuid().meta({ description: 'The squadmate to nudge.' }),
  kind: NudgeKind.meta({
    description: 'A poke (拍一拍, `poke`). The app shows each kind with its own copy.',
  }),
};

export const NudgeDraft = z
  .strictObject({ version: bodyVersion(1), ...fields })
  .openapi('NudgeDraft');
export const Nudge = z.strictObject({ version: bodyVersion(1), ...fields }).openapi('Nudge');
export const SquadNudges = z
  .strictObject({
    version: bodyVersion(1),
    kind: fields.kind,
    sent: z.array(z.uuid()).meta({
      description: 'The squadmates the caller sent one to today, on the caller’s clock.',
    }),
    received: z
      .array(
        z.strictObject({
          from: z.uuid().meta({ description: 'The squadmate who sent it.' }),
          at: z.iso.datetime().meta({ description: 'When they sent it, in UTC.' }),
        }),
      )
      .meta({
        description: 'Who sent the caller one in the last 24 hours, each once, oldest first.',
      }),
  })
  .openapi('SquadNudges');

/**
 * Squadmates nudging each other: `POST /squads/{squadId}/nudges`. A nudge isn't pushed on its
 * own; the receiver's 6pm daily push counts it and names who sent it.
 */
export function nudges(deps: { readonly verifyToken: VerifyToken; readonly nudges: Nudges }) {
  const send = createRoute({
    method: 'post',
    path: '/squads/{squadId}/nudges',
    operationId: 'nudgeSquadmate',
    summary: 'Poke a squadmate (拍一拍)',
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

  const list = createRoute({
    method: 'get',
    path: '/squads/{squadId}/nudges',
    operationId: 'listSquadNudges',
    summary: 'The caller’s pokes in a squad (拍一拍)',
    description:
      'What the home shows: whom the caller sent one to today (so it can’t be sent again), ' +
      'and who sent the caller one in the last 24 hours (they pat the caller on the home). ' +
      'Only current squadmates count.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: z.strictObject({ squadId: SquadId }),
      query: z.strictObject({ kind: fields.kind }),
    },
    responses: {
      200: {
        description: 'The caller’s nudges of that kind',
        content: { 'application/json': { schema: SquadNudges } },
      },
      400: problem('Not a valid kind'),
      401: problem('No bearer token, or not a valid one'),
      403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      503: problem('Sign-in can’t be checked right now'),
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(list, async (c) => {
      const { kind } = c.req.valid('query');
      const { sent, received } = await deps.nudges.inSquad({
        member: MemberId.parse(c.var.caller.userId),
        squad: c.req.valid('param').squadId,
        kind,
      });
      return c.json(
        {
          version: 1 as const,
          kind,
          sent: [...sent],
          received: received.map(({ from, at }) => ({ from, at: at.toISOString() })),
        },
        200,
      );
    })
    .openapi(send, async (c) => {
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
