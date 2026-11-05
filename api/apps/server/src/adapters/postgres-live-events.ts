import pg from 'pg';
import { z } from 'zod';

import { LiveEventsUnavailableError } from '../errors.js';
import type { LiveEvents, LiveListener, UserId } from '../ports.js';

/** The channel the database tells live events on (the `live_events` migration). */
const CHANNEL = 'live_events';

/** How often the listening connection is checked, so a dropped one is noticed and replaced. */
const PING_MS = 60_000;

const Payload = z.object({
  version: z.literal(1),
  member: z.uuid(),
  kind: z.string(),
  id: z.int().positive(),
});

/**
 * Live events from Postgres: one connection per server instance `LISTEN`s on the `live_events`
 * channel, which the database tells on as each event's transaction commits, so every instance
 * hears every event and hands each to the subscribers of its member.
 * https://www.postgresql.org/docs/current/sql-listen.html
 *
 * `url` must hold a session of its own: Supabase's transaction pooler (port 6543) can't `LISTEN`,
 * its session pooler (5432) and a direct connection can.
 * https://supabase.com/docs/guides/database/connecting-to-postgres#connection-pooler
 *
 * The connection opens with the first subscriber and stays open. When it drops, every subscriber
 * hears `end` (what was told meanwhile is missed, and the app reads it again on reconnecting) and
 * the next subscriber opens a new one. `onLost` hears why, for the log.
 */
export function createPostgresLiveEvents(
  url: string,
  {
    ca,
    onLost = () => undefined,
  }: { readonly ca?: string; readonly onLost?: (error: Error | undefined) => void } = {},
): LiveEvents {
  const listeners = new Map<string, Set<LiveListener>>();
  let connection: Promise<pg.Client> | undefined;
  let closed = false;

  function endAll() {
    const all = [...listeners.values()].flatMap((each) => [...each]);
    listeners.clear();
    for (const listener of all) listener.end();
  }

  function tell(payload: string | undefined) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(payload ?? '');
    } catch {
      return;
    }
    const event = Payload.safeParse(parsed);
    // A kind this build doesn't know (told by a newer migration) is left out.
    if (!event.success || event.data.kind !== 'notice') return;
    for (const listener of listeners.get(event.data.member) ?? []) {
      listener.event({ kind: 'notice', id: event.data.id });
    }
  }

  function connect(): Promise<pg.Client> {
    const client = new pg.Client({
      connectionString: url,
      connectionTimeoutMillis: 5_000,
      keepAlive: true,
      ...(ca === undefined ? {} : { ssl: { ca } }),
    });
    let ping: NodeJS.Timeout | undefined;
    const ready = (async () => {
      await client.connect();
      await client.query(`listen ${CHANNEL}`);
      ping = setInterval(() => {
        client.query('select 1').catch((error: unknown) => {
          lost(error instanceof Error ? error : undefined);
        });
      }, PING_MS);
      ping.unref();
      return client;
    })();
    const lost = (error: Error | undefined) => {
      clearInterval(ping);
      if (connection !== ready) return;
      connection = undefined;
      onLost(error);
      endAll();
      client.end().catch(() => undefined);
    };
    client.on('notification', (message) => {
      if (message.channel === CHANNEL) tell(message.payload);
    });
    client.on('error', lost);
    client.on('end', () => {
      lost(undefined);
    });
    return ready;
  }

  return {
    async subscribe(member: UserId, listener: LiveListener) {
      if (closed) throw new LiveEventsUnavailableError();
      connection ??= connect();
      const current = connection;
      try {
        await current;
      } catch (cause) {
        if (connection === current) connection = undefined;
        await current.then((client) => client.end()).catch(() => undefined);
        throw new LiveEventsUnavailableError({ cause });
      }
      // It dropped, or closed, while connecting: this subscriber would never hear its `end`.
      if (connection !== current) throw new LiveEventsUnavailableError();
      let mine = listeners.get(member);
      if (mine === undefined) {
        mine = new Set();
        listeners.set(member, mine);
      }
      mine.add(listener);
      return () => {
        const now = listeners.get(member);
        now?.delete(listener);
        if (now?.size === 0) listeners.delete(member);
      };
    },

    async close() {
      closed = true;
      const current = connection;
      connection = undefined;
      endAll();
      const client = await current?.catch(() => undefined);
      await client?.end().catch(() => undefined);
    },
  };
}
