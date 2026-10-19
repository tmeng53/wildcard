import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  DraftReason,
  DraftStyle,
  MemberId,
  type DisclaimerDrafts as DisclaimerDraftsModule,
  type DraftsOutcome,
} from '@wildcard/disclaimer-drafts';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

export const DisclaimerDraftRequest = z
  .strictObject({
    version: bodyVersion(1),
    reason: DraftReason.meta({
      description:
        'Why the member didn’t train today, as they typed it: 1 to 100 characters. Only this ' +
        'and the style go to the AI, never names, photos or squads.',
      example: '早上没起来',
    }),
    style: DraftStyle.meta({
      description: 'funny 搞笑, unhinged 发疯, heroic 中二 or stubborn 嘴硬.',
    }),
  })
  .openapi('DisclaimerDraftRequest');

const draftsFields = { version: bodyVersion(1) };

export const DisclaimerDraftList = z
  .discriminatedUnion('kind', [
    z
      .strictObject({
        ...draftsFields,
        kind: z.literal('drafts'),
        drafts: z
          .array(z.string())
          .length(3)
          .meta({
            description:
              'Three drafts to swipe through, each one line of 15 to 80 characters. The member ' +
              'may edit the one they pick before posting it.',
          }),
      })
      .meta({ description: 'Drafts to pick from.' }),
    z.strictObject({ ...draftsFields, kind: z.literal('care') }).meta({
      description:
        'The reason speaks of self-harm. No drafts: show the member the care line and the ' +
        '988 buttons. Nobody else sees anything.',
    }),
    z.strictObject({ ...draftsFields, kind: z.literal('declined') }).meta({
      description: 'The AI doesn’t write about this reason. Show the dice suggestions.',
    }),
  ])
  .openapi('DisclaimerDrafts');

function wire(outcome: DraftsOutcome): z.infer<typeof DisclaimerDraftList> {
  switch (outcome.kind) {
    case 'drafts':
      return { version: 1, kind: 'drafts', drafts: [...outcome.drafts] };
    case 'care':
      return { version: 1, kind: 'care' };
    case 'declined':
      return { version: 1, kind: 'declined' };
  }
}

/**
 * `POST /disclaimer-drafts`: three AI drafts for today's 请假条. The app calls it only when
 * the member taps the button, never as they type.
 */
export function disclaimerDrafts(deps: {
  readonly verifyToken: VerifyToken;
  readonly disclaimerDrafts: DisclaimerDraftsModule;
}) {
  const route = createRoute({
    method: 'post',
    path: '/disclaimer-drafts',
    operationId: 'writeDisclaimerDrafts',
    summary: 'Three AI drafts for a disclaimer',
    description:
      'Each member gets 6 batches in any 24 hours (the first and 5 more). A batch that fails ' +
      'doesn’t count. On any failure, show the dice suggestions instead of an error.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: {
        required: true,
        content: { 'application/json': { schema: DisclaimerDraftRequest } },
      },
    },
    responses: {
      200: {
        description: 'Drafts, the care line, or a decline',
        content: { 'application/json': { schema: DisclaimerDraftList } },
      },
      400: problem('Not a valid request'),
      401: problem('No bearer token, or not a valid one'),
      429: problem('The member has used today’s batches'),
      503: problem('Sign-in can’t be checked, or no drafts could be written, right now'),
    },
  });
  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const { reason, style } = c.req.valid('json');
    const outcome = await deps.disclaimerDrafts.write({
      member: MemberId.parse(c.var.caller.userId),
      reason,
      style,
    });
    return c.json(wire(outcome), 200);
  });
}
