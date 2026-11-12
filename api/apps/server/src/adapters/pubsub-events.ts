import { z } from 'zod';

import { topicOf, type PublishEvent } from '../events.js';
import type { Log } from '../log.js';

/** Where Cloud Run hands the server an access token for its own service account. */
export const METADATA_TOKEN_URL =
  'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token';

/** How long one try to publish may take. */
const PUBLISH_TIMEOUT_MS = 3_000;
/** How many times an event is offered to Pub/Sub before it is logged as lost. */
const PUBLISH_TRIES = 2;
/** A token is fetched again this long before Google says it expires. */
const TOKEN_MARGIN_MS = 60_000;

// Plain `z.object`: Google's answers carry more fields than we read.
const AccessToken = z.object({ access_token: z.string().min(1), expires_in: z.number() });
const Published = z.object({ messageIds: z.array(z.string()).min(1) });

/**
 * Events through Google Pub/Sub, on the hosted server: each kind to its topic in `project`
 * (`check-in-created`, …), signed with the server's own service account, which
 * `scripts/gcp-setup.sh` lets publish. Pub/Sub then pushes it to each subscriber's
 * `/jobs/events/<subscriber>`. The request never runs an event's work itself: when Pub/Sub can't
 * take it after a second try, the event is logged as an error (and so reported), and the coach
 * job catches the check-ins and comments it missed.
 * https://cloud.google.com/pubsub/docs/reference/rest/v1/projects.topics/publish
 * https://cloud.google.com/run/docs/securing/service-identity#fetching_identity_and_access_tokens
 */
export function pubSubEvents(options: {
  readonly project: string;
  readonly log: Log;
  readonly tokenUrl?: string;
  readonly pubSubUrl?: string;
  readonly now?: () => number;
}): PublishEvent {
  const now = options.now ?? Date.now;
  const pubSubUrl = options.pubSubUrl ?? 'https://pubsub.googleapis.com';
  let cached: { token: string; until: number } | undefined;

  const accessToken = async (): Promise<string> => {
    if (cached !== undefined && now() < cached.until) return cached.token;
    const response = await fetch(options.tokenUrl ?? METADATA_TOKEN_URL, {
      headers: { 'Metadata-Flavor': 'Google' },
      signal: AbortSignal.timeout(PUBLISH_TIMEOUT_MS),
    });
    if (!response.ok) throw new Error(`the metadata server answered ${String(response.status)}`);
    const { access_token: token, expires_in: seconds } = AccessToken.parse(await response.json());
    cached = { token, until: now() + seconds * 1000 - TOKEN_MARGIN_MS };
    return token;
  };

  const publishOnce = async (event: Parameters<PublishEvent>[0], topic: string): Promise<void> => {
    const response = await fetch(
      `${pubSubUrl}/v1/projects/${options.project}/topics/${topic}:publish`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${await accessToken()}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          messages: [
            {
              data: Buffer.from(JSON.stringify(event)).toString('base64'),
              attributes: { kind: event.kind },
            },
          ],
        }),
        signal: AbortSignal.timeout(PUBLISH_TIMEOUT_MS),
      },
    );
    if (!response.ok) throw new Error(`Pub/Sub answered ${String(response.status)}`);
    Published.parse(await response.json());
  };

  return async (event) => {
    const topic = topicOf(event.kind);
    for (let tried = 1; ; tried += 1) {
      try {
        await publishOnce(event, topic);
        return;
      } catch (error) {
        if (tried >= PUBLISH_TRIES) {
          options.log.error('event not published', { topic, event, error });
          return;
        }
      }
    }
  };
}
