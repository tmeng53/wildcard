import { createServer, type IncomingMessage } from 'node:http';

import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import type { ServerEvent } from '../events.js';
import { createLog } from '../log.js';
import { pubSubEvents } from './pubsub-events.js';

const event: ServerEvent = {
  version: 1,
  kind: 'check-in.created',
  checkIn: '00000000-0000-4000-8000-000000000001',
  squads: ['00000000-0000-4000-8000-000000000002'],
};

/** Google's metadata server and Pub/Sub, as one local server; `down` makes Pub/Sub refuse. */
const seen: { path: string; authorization?: string; body: string }[] = [];
let tokensHanded = 0;
let down = false;
const server = createServer((request: IncomingMessage, response) => {
  let body = '';
  request.on('data', (chunk: Buffer) => (body += chunk.toString()));
  request.on('end', () => {
    const path = request.url ?? '';
    if (path === '/token') {
      tokensHanded += 1;
      if (request.headers['metadata-flavor'] !== 'Google') response.writeHead(403).end();
      else
        response.end(
          JSON.stringify({ access_token: 'tok', expires_in: 3599, token_type: 'Bearer' }),
        );
      return;
    }
    seen.push({ path, authorization: request.headers.authorization, body });
    if (down) response.writeHead(404).end('{}');
    else response.end(JSON.stringify({ messageIds: ['1'] }));
  });
});
let base = '';
beforeAll(async () => {
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') throw new Error('not listening');
  base = `http://127.0.0.1:${String(address.port)}`;
});
afterAll(() => {
  server.close();
});

describe('events through Pub/Sub', () => {
  it('publish to their kind’s topic with the server’s token, fetched once, and when Pub/Sub refuses twice log an error, never running the work in the request', async () => {
    const logged: string[] = [];
    const publish = pubSubEvents({
      project: 'wildcard-test',
      log: createLog((line) => logged.push(line)),
      tokenUrl: `${base}/token`,
      pubSubUrl: base,
    });

    await publish(event);
    await publish(event);
    expect(tokensHanded).toBe(1);
    expect(seen).toHaveLength(2);
    expect(seen[0]?.path).toBe('/v1/projects/wildcard-test/topics/check-in-created:publish');
    expect(seen[0]?.authorization).toBe('Bearer tok');
    const sent = z
      .object({
        messages: z.array(
          z.object({ data: z.string(), attributes: z.object({ kind: z.string() }) }),
        ),
      })
      .parse(JSON.parse(seen[0]?.body ?? ''));
    expect(sent.messages[0]?.attributes.kind).toBe('check-in.created');
    expect(
      JSON.parse(Buffer.from(sent.messages[0]?.data ?? '', 'base64').toString()),
    ).toStrictEqual(event);
    expect(logged).toStrictEqual([]);

    down = true;
    await publish(event);
    expect(seen).toHaveLength(4);
    const entries = logged.map((line) =>
      z
        .object({ severity: z.string(), message: z.string(), topic: z.string() })
        .parse(JSON.parse(line)),
    );
    expect(entries).toStrictEqual([
      { severity: 'ERROR', message: 'event not published', topic: 'check-in-created' },
    ]);
  });
});
