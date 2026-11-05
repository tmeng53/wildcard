import { randomUUID } from 'node:crypto';

import { Kysely, PostgresDialect, sql } from 'kysely';
import pg from 'pg';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createPostgresChatStore, type ChatTables } from '../adapters/postgres-chat-store.js';
import { ChatEmoji, MemberId, MessageId, MessageText, SquadId } from '../domain/message.js';
import {
  ChatMessageNotFoundError,
  MessageIdTakenError,
  NotYourMessageError,
  OwnMessageReportError,
  SquadNotJoinedError,
} from '../errors.js';
import type { ChatMembership } from '../ports.js';
import { createSquadChat } from './squad-chat.js';

// Local Supabase's database, as scripts/verify.sh passes it in. Never a mocked database.
const db = new Kysely<ChatTables>({
  dialect: new PostgresDialect({
    pool: new pg.Pool({ connectionString: z.string().parse(process.env.DATABASE_URL) }),
  }),
});
afterAll(() => db.destroy());

async function newMember() {
  const id = MemberId.parse(randomUUID());
  await sql`insert into auth.users (id) values (${id})`.execute(db);
  return id;
}

/** A squad with these members, who joined at these times, kept in the database's own table. */
async function squadWith(members: readonly { member: MemberId; joinedAt: Date }[]) {
  const id = SquadId.parse(randomUUID());
  await sql`insert into public.squads (id, name, invite_code) values (${id}, 'Squad', ${id})`.execute(
    db,
  );
  for (const { member, joinedAt } of members) {
    await sql`insert into public.squad_members (squad_id, member_id, joined_at)
      values (${id}, ${member}, ${joinedAt})`.execute(db);
  }
  return id;
}

/** Membership as the squads module answers it, read from its table here for the test only. */
const membership: ChatMembership = {
  async joinedAt({ squad, member }) {
    const { rows } = await sql<{ joined_at: Date }>`select joined_at from public.squad_members
      where squad_id = ${squad} and member_id = ${member}`.execute(db);
    return rows[0]?.joined_at;
  },
  async membersOf(squad) {
    const { rows } = await sql<{ member_id: string }>`select member_id from public.squad_members
      where squad_id = ${squad} order by joined_at`.execute(db);
    return rows.map(({ member_id: id }) => MemberId.parse(id));
  },
};

const chat = createSquadChat({ store: createPostgresChatStore(db), membership });
const text = (words: string) => MessageText.parse(words);
const longAgo = new Date('2026-01-01T00:00:00Z');

async function threeMembers() {
  const [ana, bea, cy] = await Promise.all([newMember(), newMember(), newMember()]);
  const squad = await squadWith([ana, bea, cy].map((member) => ({ member, joinedAt: longAgo })));
  return { ana, bea, cy, squad };
}

function send(
  member: MemberId,
  {
    squad,
    words,
    ...more
  }: {
    squad: SquadId;
    words: string;
    replyTo?: MessageId;
    mentions?: MemberId[];
    mentionsCoach?: boolean;
  },
) {
  return chat.send({
    member,
    squad,
    id: MessageId.parse(randomUUID()),
    text: text(words),
    mentions: more.mentions ?? [],
    mentionsCoach: more.mentionsCoach ?? false,
    ...(more.replyTo === undefined ? {} : { replyTo: more.replyTo }),
  });
}

describe('squad chat', () => {
  it('saves a message once however often it is retried, and refuses its id for other words', async () => {
    const { ana, squad } = await threeMembers();
    const id = MessageId.parse(randomUUID());
    const input = {
      member: ana,
      squad,
      id,
      text: text('练腿去'),
      mentions: [],
      mentionsCoach: false,
    };
    const first = await chat.send(input);
    const again = await chat.send(input);
    expect([first.created, again.created]).toStrictEqual([true, false]);
    expect(again.message.seq).toBe(first.message.seq);
    await expect(chat.send({ ...input, text: text('别的') })).rejects.toBeInstanceOf(
      MessageIdTakenError,
    );
    const page = await chat.page({ member: ana, squad, limit: 10 });
    expect(page.messages.map(({ text: words }) => words)).toStrictEqual(['练腿去']);
  });

  it('keeps only squadmates in its @s, and never the writer', async () => {
    const { ana, bea, squad } = await threeMembers();
    const stranger = await newMember();
    const { message } = await send(ana, {
      squad,
      words: '@Bea 走',
      mentions: [bea, bea, ana, stranger],
    });
    expect(message.mentions).toStrictEqual([bea]);
  });

  it('shows a newcomer only what was sent since they joined, and what those reply to only then', async () => {
    const { ana, bea, squad } = await threeMembers();
    const before = await send(ana, { squad, words: '以前的话' });
    const newcomer = await newMember();
    await sql`insert into public.squad_members (squad_id, member_id) values (${squad}, ${newcomer})`.execute(
      db,
    );
    await send(bea, { squad, words: '欢迎', replyTo: before.message.id });
    const page = await chat.page({ member: newcomer, squad, limit: 10 });
    expect(page.messages.map(({ text: words }) => words)).toStrictEqual(['欢迎']);
    expect(page.quoted).toStrictEqual([]);
    await expect(
      send(newcomer, { squad, words: '回老消息', replyTo: before.message.id }),
    ).rejects.toBeInstanceOf(ChatMessageNotFoundError);
    const old = await chat.page({ member: ana, squad, limit: 10 });
    expect(old.messages.map(({ text: words }) => words)).toStrictEqual(['欢迎', '以前的话']);
  });

  it('pages newest first, and says when there is more', async () => {
    const { ana, squad } = await threeMembers();
    for (const words of ['一', '二', '三']) await send(ana, { squad, words });
    const first = await chat.page({ member: ana, squad, limit: 2 });
    expect(first.messages.map(({ text: words }) => words)).toStrictEqual(['三', '二']);
    expect(first.more).toBe(true);
    const last = first.messages.at(-1);
    const next = await chat.page({ member: ana, squad, limit: 2, before: last?.seq ?? 0 });
    expect(next.messages.map(({ text: words }) => words)).toStrictEqual(['一']);
    expect(next.more).toBe(false);
  });

  it('refuses anyone outside the squad', async () => {
    const { squad } = await threeMembers();
    const stranger = await newMember();
    await expect(chat.page({ member: stranger, squad, limit: 10 })).rejects.toBeInstanceOf(
      SquadNotJoinedError,
    );
    await expect(send(stranger, { squad, words: '嗨' })).rejects.toBeInstanceOf(
      SquadNotJoinedError,
    );
  });

  it('lets only the writer delete a message, and a reply to it stays as a plain message', async () => {
    const { ana, bea, squad } = await threeMembers();
    const { message } = await send(ana, { squad, words: '删掉我' });
    const reply = await send(bea, { squad, words: '收到', replyTo: message.id });
    await expect(chat.remove({ member: bea, squad, message: message.id })).rejects.toBeInstanceOf(
      NotYourMessageError,
    );
    await chat.remove({ member: ana, squad, message: message.id });
    expect(await chat.find(squad, message.id)).toBeUndefined();
    expect((await chat.find(squad, reply.message.id))?.replyTo).toBeUndefined();
  });

  it('keeps one reaction per member, which they change or take off', async () => {
    const { ana, bea, squad } = await threeMembers();
    const { message } = await send(ana, { squad, words: '今天 5 公里' });
    await chat.react({ member: bea, squad, message: message.id, emoji: ChatEmoji.parse('🔥') });
    const changed = await chat.react({
      member: bea,
      squad,
      message: message.id,
      emoji: ChatEmoji.parse('💪'),
    });
    expect(changed.reactions).toStrictEqual([{ member: bea, emoji: '💪' }]);
    const off = await chat.react({ member: bea, squad, message: message.id, emoji: undefined });
    expect(off.reactions).toStrictEqual([]);
  });

  it('keeps a report with what it said, even once the message is deleted, but never of one’s own', async () => {
    const { ana, bea, squad } = await threeMembers();
    const { message } = await send(ana, { squad, words: '不好的话' });
    await expect(chat.report({ member: ana, squad, message: message.id })).rejects.toBeInstanceOf(
      OwnMessageReportError,
    );
    await chat.report({ member: bea, squad, message: message.id });
    await chat.report({ member: bea, squad, message: message.id });
    await chat.remove({ member: ana, squad, message: message.id });
    const reports = (await chat.reports({ limit: 200 })).filter((each) => each.squad === squad);
    expect(
      reports.map(({ text, message: id, writer, reporter }) => ({ text, id, writer, reporter })),
    ).toStrictEqual([{ text: '不好的话', id: undefined, writer: ana, reporter: bea }]);
  });

  it('counts what a member hasn’t read, and the @s and replies to them in it', async () => {
    const { ana, bea, squad } = await threeMembers();
    const mine = await send(ana, { squad, words: '我的' });
    await send(bea, { squad, words: '大家好' });
    await send(bea, { squad, words: '@Ana', mentions: [ana] });
    await send(bea, { squad, words: '回你', replyTo: mine.message.id });
    expect(await chat.unread({ member: ana, squad })).toStrictEqual({ count: 3, mentions: 2 });
    const page = await chat.page({ member: ana, squad, limit: 1 });
    await chat.markRead({ member: ana, squad, seq: page.messages[0]?.seq ?? 0 });
    // Never back.
    await chat.markRead({ member: ana, squad, seq: 1 });
    expect(await chat.unread({ member: ana, squad })).toStrictEqual({ count: 0, mentions: 0 });
  });

  it('pushes by each member’s alerts: @s and replies by default, all, or none', async () => {
    const { ana, bea, cy, squad } = await threeMembers();
    expect(await chat.alerts({ member: bea, squad })).toBe('mentions');
    await chat.setAlerts({ member: cy, squad, alerts: 'all' });
    await chat.setAlerts({ member: cy, squad, alerts: 'all' });
    const plain = await send(ana, { squad, words: '出发' });
    expect(await chat.pushTargets(plain)).toStrictEqual([{ member: cy, mentioned: false }]);
    const mention = await send(ana, { squad, words: '@Bea', mentions: [bea] });
    // In no particular order.
    expect(
      (await chat.pushTargets(mention)).toSorted(
        (one, other) => (one.mentioned ? -1 : 0) - (other.mentioned ? -1 : 0),
      ),
    ).toStrictEqual([
      { member: bea, mentioned: true },
      { member: cy, mentioned: false },
    ]);
    await chat.setAlerts({ member: bea, squad, alerts: 'none' });
    expect(await chat.pushTargets(mention)).toStrictEqual([{ member: cy, mentioned: false }]);
    const logged = await db
      .selectFrom('squad_chat_alerts')
      .select('alerts')
      .where('squad_id', '=', squad)
      .orderBy('id')
      .execute();
    expect(logged.map(({ alerts }) => alerts)).toStrictEqual(['all', 'none']);
  });

  it('saves the coach’s answer to a message once, and its 战术板 line once a day', async () => {
    const { ana, squad } = await threeMembers();
    const { message } = await send(ana, { squad, words: '@毛头 今天练什么', mentionsCoach: true });
    const coach = 'xiaohun';
    const first = await chat.coachAnswer({ squad, coach, replyTo: message.id, text: '深蹲' });
    const retry = await chat.coachAnswer({ squad, coach, replyTo: message.id, text: '卧推' });
    expect([first.created, retry.created, retry.message.text]).toStrictEqual([true, false, '深蹲']);
    const note = await chat.coachNote({ squad, coach, day: '2026-11-04', text: '今天腿日' });
    const noteAgain = await chat.coachNote({ squad, coach, day: '2026-11-04', text: '换一句' });
    expect([note.created, noteAgain.created, noteAgain.message.kind]).toStrictEqual([
      true,
      false,
      'note',
    ]);
    const recent = await chat.recent({ squad, upTo: note.message.seq, limit: 10 });
    expect(recent.map(({ text: words }) => words)).toStrictEqual([
      '@毛头 今天练什么',
      '深蹲',
      '今天腿日',
    ]);
  });
});
