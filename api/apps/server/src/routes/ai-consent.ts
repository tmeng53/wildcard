import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  AiConsentTerms,
  AiProvider,
  MemberId,
  type AiConsent as AiConsentModule,
  type AiConsentState,
} from '@wildcard/ai-consent';
import type { Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import { withdrawAiConsent } from '../flows/withdraw-ai-consent.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const termsFields = {
  copyVersion: AiConsentTerms.shape.copyVersion.meta({
    description: 'The version of the consent copy, which the app’s String Catalog holds.',
    example: 1,
  }),
  provider: AiProvider.meta({
    description: 'The AI provider the copy names: the one members’ words are sent to.',
  }),
};

const Terms = z.strictObject(termsFields).openapi('AiConsentTerms');

/** A member's AI consent, as `GET`, `PUT /me/ai-consent` return it. */
export const AiConsent = z
  .strictObject({
    version: bodyVersion(1),
    terms: Terms.meta({ description: 'What the member must agree to now.' }),
    given: z
      .strictObject({
        ...termsFields,
        givenAt: z.iso.datetime().meta({ description: 'When they agreed, in UTC.' }),
      })
      .optional()
      .meta({
        description:
          'The member’s latest consent: left out when they never gave one or withdrew it. It ' +
          'may be to older terms.',
      }),
    current: z.boolean().meta({
      description:
        'True when `given` is to `terms`. Joining or making a squad, AI drafts and the weekly ' +
        'awards need it; when false, show the copy for `terms` and ask.',
    }),
  })
  .openapi('AiConsent');

export const AiConsentGiven = z
  .strictObject({ version: bodyVersion(1), ...termsFields })
  .meta({ description: 'The terms the app showed the member, who agreed to them.' })
  .openapi('AiConsentGiven');

function wire(state: AiConsentState): z.infer<typeof AiConsent> {
  return {
    version: 1,
    terms: state.terms,
    ...(state.given === undefined
      ? {}
      : { given: { ...state.given.terms, givenAt: state.given.givenAt.toISOString() } }),
    current: state.current,
  };
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET`, `PUT` and `DELETE /me/ai-consent`: the member's consent to having their captions and
 * 请假条 sent to the AI provider, which being in a squad needs.
 */
export function aiConsent(deps: {
  readonly verifyToken: VerifyToken;
  readonly aiConsent: AiConsentModule;
  readonly squads: Squads;
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
      'Whether they have agreed to the current terms, so a returning member isn’t asked again.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: { 200: consentResponse('Their consent'), ...signedInFailures },
  });

  const give = createRoute({
    method: 'put',
    path: '/me/ai-consent',
    operationId: 'putMyAiConsent',
    summary: 'Agree to the AI terms',
    description:
      'With the terms the app showed, which must be the current ones. Safe to repeat: agreeing ' +
      'again keeps when they first agreed.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: AiConsentGiven } } },
    },
    responses: {
      200: consentResponse('Agreed'),
      400: problem(
        'Not a valid request, or terms that aren’t the current ones ' +
          '(`AI_CONSENT_TERMS_OUTDATED`): read them again and ask again',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const withdraw = createRoute({
    method: 'delete',
    path: '/me/ai-consent',
    operationId: 'deleteMyAiConsent',
    summary: 'Withdraw the AI consent',
    description:
      'Being in a squad needs it, so the member leaves every squad they are in, as leaving one ' +
      'does. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: { 204: { description: 'Withdrawn, and out of every squad' }, ...signedInFailures },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(find, async (c) => {
      const state = await deps.aiConsent.find(MemberId.parse(c.var.caller.userId));
      return c.json(wire(state), 200);
    })
    .openapi(give, async (c) => {
      const { copyVersion, provider } = c.req.valid('json');
      const state = await deps.aiConsent.give({
        member: MemberId.parse(c.var.caller.userId),
        terms: { copyVersion, provider },
      });
      return c.json(wire(state), 200);
    })
    .openapi(withdraw, async (c) => {
      await withdrawAiConsent(deps, c.var.caller.userId);
      return c.body(null, 204);
    });
}
