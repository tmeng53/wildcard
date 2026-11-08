import { setTimeout as wait } from 'node:timers/promises';

import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { PhotoNotUploadedError, PhotoNotYoursError } from '@wildcard/check-ins';
import {
  AppInfo,
  FEEDBACK_DAILY_LIMIT,
  FeedbackBody,
  FEEDBACK_MAX_SCREENSHOTS,
  FeedbackId,
  FeedbackKind,
  MemberId,
  type FeedbackInbox,
} from '@wildcard/feedback';

import { bodyVersion } from '../body-version.js';
import { fileFeedback, type FeedbackIssueDependencies } from '../flows/feedback-issues.js';
import { PhotoPath, isOwnPhoto, type PhotoStorage, type VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

/** How long the answer waits for the issue; a slower one carries on, and the jobs catch up. */
const FILE_WAIT_MS = 5000;

export const FeedbackDraft = z
  .strictObject({
    version: bodyVersion(1),
    id: z.uuid().meta({ description: 'Made by the app, so sending again saves it once.' }),
    kind: FeedbackKind.meta({
      description: '出问题了 (`problem`) or 提个建议 (`idea`).',
    }),
    body: FeedbackBody,
    screenshots: z.array(PhotoPath).max(FEEDBACK_MAX_SCREENSHOTS).meta({
      description:
        'Up to 3 screenshots, uploaded first through `POST /photo-uploads` and listed by path.',
    }),
    app: AppInfo.meta({
      description:
        'Which app sent it (version, build, iOS version, device model, language), so whoever ' +
        'fixes it knows where to look.',
    }),
  })
  .openapi('FeedbackDraft');

export const FeedbackSent = z
  .strictObject({ version: bodyVersion(1), id: z.uuid() })
  .openapi('FeedbackSent');

/**
 * `POST /feedback`: 意见反馈, a member's message to us from 设置 › 关于. It is saved, then filed
 * as an issue in our private feedback repository (with the screenshots, the app it came from
 * and the member's id, never their name or email), where agents pick it up.
 */
export function feedback(
  deps: {
    readonly verifyToken: VerifyToken;
    readonly feedback: FeedbackInbox;
    readonly photos: PhotoStorage;
  } & Omit<FeedbackIssueDependencies, 'feedback' | 'photos'>,
) {
  const route = createRoute({
    method: 'post',
    path: '/feedback',
    operationId: 'sendFeedback',
    summary: 'Send us feedback (意见反馈)',
    description:
      `Up to ${String(FEEDBACK_DAILY_LIMIT)} a day; the same id again saves nothing new, so it ` +
      'is safe to repeat. Needs no squad.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: FeedbackDraft } } },
    },
    responses: {
      200: {
        description: 'Sent already',
        content: { 'application/json': { schema: FeedbackSent } },
      },
      201: { description: 'Sent', content: { 'application/json': { schema: FeedbackSent } } },
      400: problem(
        'Not valid feedback (`FEEDBACK_INVALID`), or a screenshot not uploaded (`PHOTO_NOT_UPLOADED`)',
      ),
      401: problem('No bearer token, or not a valid one'),
      403: problem('A screenshot in someone else’s folder (`PHOTO_NOT_YOURS`)'),
      409: problem('Another member’s message has this id (`FEEDBACK_ID_TAKEN`)'),
      429: problem('As many messages as a day allows (`FEEDBACK_LIMIT`)'),
      ...jsonBodyFailures,
      503: problem('Sign-in or photo storage can’t be reached right now'),
    },
  });

  return new OpenAPIHono<SignedIn>().openapi(route, async (c) => {
    const draft = c.req.valid('json');
    const member = MemberId.parse(c.var.caller.userId);
    const paths = draft.screenshots;
    const notYours = paths.find((path) => !isOwnPhoto(path, member));
    if (notYours !== undefined) throw new PhotoNotYoursError(notYours);
    const uploaded = await Promise.all(paths.map((path) => deps.photos.exists(path)));
    const missing = paths.find((_path, index) => uploaded[index] !== true);
    if (missing !== undefined) throw new PhotoNotUploadedError(missing);

    const { outcome, feedback: saved } = await deps.feedback.send({
      id: FeedbackId.parse(draft.id),
      member,
      kind: draft.kind,
      body: draft.body,
      screenshots: paths,
      app: draft.app,
    });
    if (outcome === 'created') {
      const stop = new AbortController();
      const late = wait(FILE_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(
        () => undefined,
      );
      await Promise.race([fileFeedback({ ...deps, feedback: deps.feedback }, saved), late]);
      stop.abort();
    }
    const body = { version: 1 as const, id: draft.id };
    return outcome === 'created' ? c.json(body, 201) : c.json(body, 200);
  });
}
