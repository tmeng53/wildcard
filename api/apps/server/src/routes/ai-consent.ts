import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  CopyVersion,
  MemberId,
  type AiConsent as AiConsentModule,
  type AiConsentState,
} from '@wildcard/ai-consent';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const copyVersion = (description: string) => CopyVersion.meta({ description, example: 1 });

/** A member's AI consent, as `GET` and `PUT /me/ai-consent` return it. */
export const AiConsent = z
  .strictObject({
    version: bodyVersion(1),
    copyVersion: copyVersion(
      'The version of the consent copy (in the app’s String Catalog, naming the AI providers) ' +
        'the member must agree to now.',
    ),
    given: z
      .strictObject({
        copyVersion: copyVersion('The version they agreed to.'),
        givenAt: z.iso.datetime().meta({ description: 'When they agreed, in UTC.' }),
      })
      .optional()
      .meta({
        description:
          'The member’s latest consent, left out when they never gave one. It may be to an ' +
          'older version.',
      }),
    current: z.boolean().meta({
      description:
        'True when `given` is to `copyVersion`. Making or joining a squad and AI drafts need ' +
        'it; when false, show that version of the copy and ask.',
    }),
  })
  .openapi('AiConsent');

export const AiConsentGiven = z
  .strictObject({
    version: bodyVersion(1),
    copyVersion: copyVersion('The version of the copy the app showed the member, who agreed.'),
  })
  .openapi('AiConsentGiven');

function wire(state: AiConsentState): z.infer<typeof AiConsent> {
  return {
    version: 1,
    copyVersion: state.copyVersion,
    ...(state.given === undefined
      ? {}
      : {
          given: {
            copyVersion: state.given.copyVersion,
            givenAt: state.given.givenAt.toISOString(),
          },
        }),
    current: state.current,
  };
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET` and `PUT /me/ai-consent`: the member's consent to having their captions and 请假条 sent
 * to AI providers, which being in a squad needs. It can't be withdrawn on its own: deleting the
 * account (`DELETE /me`) deletes it.
 */
export function aiConsent(deps: {
  readonly verifyToken: VerifyToken;
  readonly aiConsent: AiConsentModule;
}) {
  const consentResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: AiConsent } },
  });

  const find = createRoute({
    method: 'get',
    path: '/me/ai-consent',
    operationId: 'getMyAiConsent',
    summary: 'The signed-in member’s AI consent',
    description:
      'Whether they have agreed to the current copy, so a returning member isn’t asked again.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: { 200: consentResponse('Their consent'), ...signedInFailures },
  });

  const give = createRoute({
    method: 'put',
    path: '/me/ai-consent',
    operationId: 'putMyAiConsent',
    summary: 'Agree to the AI copy',
    description:
      'With the version of the copy the app showed, which must be the current one. Safe to ' +
      'repeat: agreeing again keeps when they first agreed.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: AiConsentGiven } } },
    },
    responses: {
      200: consentResponse('Agreed'),
      400: problem(
        'Not a valid request, or a version that isn’t the current one ' +
          '(`AI_CONSENT_COPY_OUTDATED`): read the current version and ask again',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(find, async (c) => {
      const state = await deps.aiConsent.find(MemberId.parse(c.var.caller.userId));
      return c.json(wire(state), 200);
    })
    .openapi(give, async (c) => {
      const state = await deps.aiConsent.give({
        member: MemberId.parse(c.var.caller.userId),
        copyVersion: c.req.valid('json').copyVersion,
      });
      return c.json(wire(state), 200);
    });
}
