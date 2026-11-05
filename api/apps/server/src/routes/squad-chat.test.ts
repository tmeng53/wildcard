// The squad's chat over the real database and sign-in, as the app calls it.
import { randomUUID } from 'node:crypto';

import { OpenAPIHono } from '@hono/zod-openapi';
import { Character, MemberId as ProfileMember } from '@wildcard/members';
import type { PushNotification } from '@wildcard/push';
import { InviteCode, MemberId, SquadId, SquadName } from '@wildcard/squads';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from '../adapters/postgres.js';
import { createSupabaseTokenVerifier } from '../adapters/supabase-auth.js';
import { createLog } from '../log.js';
import { problemResponse } from '../problem.js';
import { chatOn, config, signUp, squadsOn } from '../test-kit/local-supabase.js';
import { squadChat } from './squad-chat.js';

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());
const chat = chatOn(db);
const squads = squadsOn(db);

const pushed: { member: string; notification: PushNotification }[] = [];
const asked: { squad: string; message: string }[] = [];
const character = Character.parse({
  nickname: '安安',
  look: { persona: 'deadpan', variants: { body: 'peach' }, colors: {} },
});

const app = new OpenAPIHono()
  .route(
    '/',
    squadChat({
      verifyToken: createSupabaseTokenVerifier({ supabaseUrl: config.supabaseUrl }),
      chat,
      // Every writer has a name, as a member past sign-up does.
      members: {
        squadmates: (members) =>
          Promise.resolve(
            new Map(
              members.map((member) => [
                ProfileMember.parse(member),
                {
                  catchphrase: null,
                  character,
                  jerseyNumber: null,
                  joinedAt: new Date(0),
                  equippedTitle: null,
                },
              ]),
            ),
          ),
      },
      push: {
        settingsOf: () => Promise.resolve({ dailyProgress: true }),
        notifyMembers: ({ members, notification }) => {
          for (const member of members) pushed.push({ member, notification });
          return Promise.resolve({ sent: members.length, gone: 0, off: 0, failures: [] });
        },
      },
      coachNames: () => Promise.resolve(new Map([['xiaohun', '小混']])),
      chatCoachAnswer: (message) => {
        asked.push(message);
        return Promise.resolve();
      },
      log: createLog(() => undefined),
    }),
  )
  .onError((thrown) => problemResponse(thrown));

async function call({
  method,
  path,
  token,
  body,
}: {
  method: string;
  path: string;
  token: string;
  body?: unknown;
}) {
  const response = await app.request(path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  return {
    status: response.status,
    body: text === '' ? undefined : z.unknown().parse(JSON.parse(text)),
  };
}

/** A squad `captain` made, with `others` in it. */
async function squadOf(captain: { userId: string }, ...others: { userId: string }[]) {
  const made = await squads.create({
    id: SquadId.parse(randomUUID()),
    creator: MemberId.parse(captain.userId),
    name: SquadName.parse('早八跑团'),
  });
  for (const other of others) {
    await squads.join({
      inviteCode: InviteCode.parse(made.squad.inviteCode),
      member: MemberId.parse(other.userId),
    });
  }
  return made.squad.id;
}

const Message = z.object({
  id: z.uuid(),
  seq: z.number(),
  member: z.uuid().optional(),
  text: z.string(),
  mentions: z.array(z.uuid()),
  reactions: z.array(z.object({ member: z.uuid(), emoji: z.string() })),
});
const Page = z.object({
  messages: z.array(Message),
  quoted: z.array(Message),
  more: z.boolean(),
  readThrough: z.number(),
  alerts: z.string(),
});
const reason = (response: { readonly body?: unknown }) =>
  z.object({ reason: z.string() }).safeParse(response.body).data?.reason;

function send(
  member: { token: string },
  {
    squad,
    id = randomUUID(),
    ...body
  }: { readonly squad: string; readonly id?: string } & Record<string, unknown>,
) {
  return call({
    method: 'PUT',
    path: `/squads/${squad}/chat/messages/${id}`,
    token: member.token,
    body: { version: 1, ...body },
  });
}

describe('the squad chat', () => {
  it('sends a message once however often it is retried, and lists it newest first', async () => {
    const [ana, bea] = await Promise.all([signUp(), signUp()]);
    const squad = await squadOf(ana, bea);
    const id = randomUUID();
    const first = await send(ana, { squad, id, text: '  早上好 ' });
    const again = await send(ana, { squad, id, text: '早上好' });
    expect([first.status, again.status]).toStrictEqual([201, 200]);
    await send(bea, { squad, text: '走起', replyTo: id });
    const page = Page.parse(
      (await call({ method: 'GET', path: `/squads/${squad}/chat/messages`, token: bea.token }))
        .body,
    );
    expect(page.messages.map(({ text }) => text)).toStrictEqual(['走起', '早上好']);
    expect(page).toMatchObject({ more: false, readThrough: 0, alerts: 'mentions', quoted: [] });
  });

  it('refuses whoever isn’t in the squad', async () => {
    const [ana, stranger] = await Promise.all([signUp(), signUp()]);
    const squad = await squadOf(ana);
    const listed = await call({
      method: 'GET',
      path: `/squads/${squad}/chat/messages`,
      token: stranger.token,
    });
    expect([listed.status, reason(listed)]).toStrictEqual([403, 'SQUAD_NOT_JOINED']);
    const sent = await send(stranger, { squad, text: '嗨' });
    expect(sent.status).toBe(403);
  });

  it('pushes an @ to whom it names, and every message to those who chose all', async () => {
    const [ana, bea, cy] = await Promise.all([signUp(), signUp(), signUp()]);
    const squad = await squadOf(ana, bea, cy);
    const all = await call({
      method: 'PUT',
      path: `/squads/${squad}/chat/alerts`,
      token: cy.token,
      body: { version: 1, alerts: 'all' },
    });
    expect(all.body).toStrictEqual({ version: 1, alerts: 'all' });
    pushed.length = 0;
    await send(ana, { squad, text: '@Bea 今晚练吗', mentions: [bea.userId] });
    expect(
      pushed.map(({ member, notification }) => [member, notification.alert.key]).toSorted(),
    ).toStrictEqual(
      [
        [bea.userId, 'push.chat.mention'],
        [cy.userId, 'push.chat'],
      ].toSorted(),
    );
    expect(pushed[0]?.notification).toMatchObject({
      category: 'chat',
      event: { kind: 'chat', squad },
    });
  });

  it('has the coach answer a message that @s it, and not a plain one', async () => {
    const ana = await signUp();
    const squad = await squadOf(ana);
    asked.length = 0;
    await send(ana, { squad, text: '今天练啥' });
    const id = randomUUID();
    await send(ana, { squad, id, text: '@小混 今天练啥', mentionsCoach: true });
    expect(asked).toStrictEqual([{ squad, message: id }]);
  });

  it('reacts, deletes only one’s own, reports someone else’s, and counts what is unread', async () => {
    const [ana, bea] = await Promise.all([signUp(), signUp()]);
    const squad = await squadOf(ana, bea);
    const id = randomUUID();
    await send(ana, { squad, id, text: '5 公里打卡' });
    const reacted = await call({
      method: 'PUT',
      path: `/squads/${squad}/chat/messages/${id}/reaction`,
      token: bea.token,
      body: { version: 1, emoji: '🔥' },
    });
    expect(Message.parse(reacted.body).reactions).toStrictEqual([
      { member: bea.userId, emoji: '🔥' },
    ]);
    const unread = await call({
      method: 'GET',
      path: `/squads/${squad}/chat/unread`,
      token: bea.token,
    });
    expect(unread.body).toStrictEqual({ version: 1, count: 1, mentions: 0 });
    const seq = Message.parse(reacted.body).seq;
    const read = await call({
      method: 'PUT',
      path: `/squads/${squad}/chat/read`,
      token: bea.token,
      body: { version: 1, seq },
    });
    expect(read.status).toBe(204);
    const after = await call({
      method: 'GET',
      path: `/squads/${squad}/chat/unread`,
      token: bea.token,
    });
    expect(after.body).toStrictEqual({ version: 1, count: 0, mentions: 0 });
    const reported = await call({
      method: 'POST',
      path: `/squads/${squad}/chat/messages/${id}/report`,
      token: bea.token,
    });
    expect(reported.status).toBe(204);
    const notTheirs = await call({
      method: 'DELETE',
      path: `/squads/${squad}/chat/messages/${id}`,
      token: bea.token,
    });
    expect([notTheirs.status, reason(notTheirs)]).toStrictEqual([403, 'NOT_YOUR_MESSAGE']);
    const deleted = await call({
      method: 'DELETE',
      path: `/squads/${squad}/chat/messages/${id}`,
      token: ana.token,
    });
    expect(deleted.status).toBe(204);
    const gone = await call({
      method: 'PUT',
      path: `/squads/${squad}/chat/messages/${id}/reaction`,
      token: bea.token,
      body: { version: 1, emoji: '👏' },
    });
    expect([gone.status, reason(gone)]).toStrictEqual([404, 'CHAT_MESSAGE_NOT_FOUND']);
  });
});
