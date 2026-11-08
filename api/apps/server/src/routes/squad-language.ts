import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { ReaderLanguage } from '@wildcard/language-model';
import type { Members } from '@wildcard/members';
import { MemberId, SquadId, type Squads } from '@wildcard/squads';

import { bodyVersion } from '../body-version.js';
import { squadLanguages } from '../flows/squad-language.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const squadLanguageField = ReaderLanguage.meta({
  description:
    'The squad’s language (小队语言): what the AI writes everything the whole squad reads in, ' +
    'its coach’s 战术板 and name and the weekly awards. What one member reads keeps their own ' +
    'app’s language.',
  example: 'zh-Hant',
});

const SquadLanguageBody = z
  .strictObject({
    version: bodyVersion(1),
    language: squadLanguageField.meta({
      description: 'The squad’s language now: the captain’s pick, else the captain’s app language.',
    }),
    canChange: z.boolean().meta({ description: 'True for the captain, the only one who sets it.' }),
  })
  .openapi('SquadLanguage');

const SquadLanguageChange = z
  .strictObject({ version: bodyVersion(1), language: squadLanguageField })
  .openapi('SquadLanguageChange');

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/** `GET` and `PUT /squads/{squadId}/language`: the squad's language (小队语言). */
export function squadLanguage(deps: {
  readonly verifyToken: VerifyToken;
  readonly squads: Squads;
  readonly members: Pick<Members, 'languages'>;
}) {
  const params = z.strictObject({ squadId: SquadId });
  const languageResponse = (description: string) => ({
    description,
    content: { 'application/json': { schema: SquadLanguageBody } },
  });

  const read = createRoute({
    method: 'get',
    path: '/squads/{squadId}/language',
    operationId: 'getSquadLanguage',
    summary: 'The squad’s language',
    description: 'For its members.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params },
    responses: {
      200: languageResponse('The language'),
      400: problem('Not a valid squad id'),
      403: problem('The member isn’t in this squad (`SQUAD_NOT_JOINED`)'),
      ...signedInFailures,
    },
  });

  const change = createRoute({
    method: 'put',
    path: '/squads/{squadId}/language',
    operationId: 'setSquadLanguage',
    summary: 'Set the squad’s language',
    description: 'For the captain. It counts at once, for what the AI writes next. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params,
      body: { required: true, content: { 'application/json': { schema: SquadLanguageChange } } },
    },
    responses: {
      200: languageResponse('The language, changed'),
      400: problem('Not a valid squad id'),
      403: problem(
        'The member isn’t in this squad (`SQUAD_NOT_JOINED`), or isn’t its captain ' +
          '(`NOT_SQUAD_CAPTAIN`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  async function body(
    squad: SquadId,
    viewer: MemberId,
  ): Promise<z.infer<typeof SquadLanguageBody>> {
    // `find` also refuses anyone outside the squad.
    const found = await deps.squads.find({ squad, viewer });
    const { squad: language } = await squadLanguages(deps, { squad, members: [] });
    return { version: 1, language, canChange: found.captain === viewer };
  }

  return new OpenAPIHono<SignedIn>()
    .openapi(read, async (c) => {
      const { squadId } = c.req.valid('param');
      return c.json(await body(squadId, MemberId.parse(c.var.caller.userId)), 200);
    })
    .openapi(change, async (c) => {
      const { squadId } = c.req.valid('param');
      const member = MemberId.parse(c.var.caller.userId);
      await deps.squads.setLanguage({
        squad: squadId,
        member,
        language: c.req.valid('json').language,
      });
      return c.json(await body(squadId, member), 200);
    });
}
