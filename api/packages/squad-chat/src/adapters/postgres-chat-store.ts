import { sql, type Kysely, type Selectable } from 'kysely';

import {
  ChatAlerts,
  ChatEmoji,
  MemberId,
  MessageId,
  SquadId,
  type ChatMessage,
} from '../domain/message.js';
import type { ChatStore } from '../ports.js';
import type { DB, SquadMessages } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type ChatTables = DB;

/** The chat store on Postgres (`supabase/migrations`). */
export function createPostgresChatStore(db: Kysely<ChatTables>): ChatStore {
  /** The messages these rows are, each with its reactions. */
  async function withReactions(rows: readonly Selectable<SquadMessages>[]): Promise<ChatMessage[]> {
    if (rows.length === 0) return [];
    const reactions = await db
      .selectFrom('squad_message_reactions')
      .select(['message_id', 'member_id', 'emoji'])
      .where(
        'message_id',
        'in',
        rows.map(({ id }) => id),
      )
      .orderBy('at')
      .orderBy('member_id')
      .execute();
    const byMessage = new Map<string, { member: MemberId; emoji: ChatEmoji }[]>();
    for (const { message_id: id, member_id: member, emoji } of reactions) {
      const list = byMessage.get(id) ?? [];
      list.push({ member: MemberId.parse(member), emoji: ChatEmoji.parse(emoji) });
      byMessage.set(id, list);
    }
    return rows.map((row) => toMessage(row, byMessage.get(row.id) ?? []));
  }

  async function one(rows: Promise<Selectable<SquadMessages> | undefined>) {
    const row = await rows;
    return row === undefined ? undefined : (await withReactions([row]))[0];
  }

  const messages = () => db.selectFrom('squad_messages').selectAll();

  return {
    async add(message) {
      const base = {
        squad_id: message.squad,
        text: message.text,
        ...(message.author.kind === 'member'
          ? { member_id: message.author.member }
          : { coach_id: message.author.coach }),
      };
      let values;
      let existing;
      if ('id' in message) {
        values = {
          ...base,
          id: message.id,
          kind: 'text',
          reply_to: message.replyTo ?? null,
          mentions: [...message.mentions],
          mentions_coach: message.mentionsCoach,
        };
        existing = () => messages().where('id', '=', message.id);
      } else if ('noteDay' in message) {
        values = { ...base, kind: 'note', note_day: message.noteDay };
        existing = () =>
          messages()
            .where('squad_id', '=', message.squad)
            .where('kind', '=', 'note')
            .where('note_day', '=', message.noteDay);
      } else {
        values = { ...base, kind: 'text', reply_to: message.replyTo };
        existing = () =>
          messages()
            .where('reply_to', '=', message.replyTo)
            .where('coach_id', 'is not', null)
            .where('kind', '=', 'text');
      }
      // A retry, or two tries at once, keeps the first one written.
      const inserted = await db
        .insertInto('squad_messages')
        .values(values)
        .onConflict((conflict) => conflict.doNothing())
        .returningAll()
        .executeTakeFirst();
      if (inserted !== undefined) {
        const [saved] = await withReactions([inserted]);
        if (saved !== undefined) return { message: saved, created: true };
      }
      const saved = await one(existing().executeTakeFirst());
      // A conflict on the id is a message saved already; it is always there to find.
      if (saved === undefined) throw new Error('The message saved meanwhile is gone.');
      return { message: saved, created: false };
    },

    find: (squad, id) =>
      one(messages().where('squad_id', '=', squad).where('id', '=', id).executeTakeFirst()),

    async page({ squad, since, before, limit }) {
      let query = messages()
        .where('squad_id', '=', squad)
        .where('created_at', '>=', since)
        .orderBy('seq', 'desc')
        .limit(limit);
      if (before !== undefined) query = query.where('seq', '<', String(before));
      return withReactions(await query.execute());
    },

    bySeq: (squad, seq) =>
      one(
        messages().where('squad_id', '=', squad).where('seq', '=', String(seq)).executeTakeFirst(),
      ),

    async remove(id) {
      await db.deleteFrom('squad_messages').where('id', '=', id).execute();
    },

    async react({ message, member, emoji }) {
      if (emoji === undefined) {
        await db
          .deleteFrom('squad_message_reactions')
          .where('message_id', '=', message)
          .where('member_id', '=', member)
          .execute();
        return;
      }
      await db
        .insertInto('squad_message_reactions')
        .values({ message_id: message, member_id: member, emoji })
        .onConflict((conflict) =>
          conflict
            .columns(['message_id', 'member_id'])
            .doUpdateSet({ emoji, at: sql`now()` })
            // The same emoji again changes nothing, and tells no one.
            .where('squad_message_reactions.emoji', '<>', emoji),
        )
        .execute();
    },

    async report({ message, member }) {
      await db
        .insertInto('squad_message_reports')
        .values({
          squad_id: message.squad,
          message_id: message.id,
          reported_member_id: message.author.kind === 'member' ? message.author.member : null,
          reported_text: message.text,
          member_id: member,
        })
        .onConflict((conflict) => conflict.columns(['message_id', 'member_id']).doNothing())
        .execute();
    },

    async alerts(squad, members) {
      if (members.length === 0) return new Map();
      const rows = await db
        .selectFrom('squad_chat_alerts')
        .distinctOn('member_id')
        .select(['member_id', 'alerts'])
        .where('squad_id', '=', squad)
        .where('member_id', 'in', members)
        .orderBy('member_id')
        .orderBy('id', 'desc')
        .execute();
      return new Map(
        rows.map(({ member_id: member, alerts }) => [
          MemberId.parse(member),
          ChatAlerts.parse(alerts),
        ]),
      );
    },

    async setAlerts({ squad, member, alerts }) {
      // Only a change is logged: the newest row is the setting, so the same one again adds none.
      await sql`
        insert into public.squad_chat_alerts (squad_id, member_id, alerts)
        select ${squad}, ${member}, ${alerts}
        where coalesce((
          select alerts from public.squad_chat_alerts
          where squad_id = ${squad} and member_id = ${member}
          order by id desc limit 1
        ), 'mentions') <> ${alerts}
      `.execute(db);
    },

    async readThrough(squad, member) {
      const row = await db
        .selectFrom('squad_chat_reads')
        .select('read_through')
        .where('squad_id', '=', squad)
        .where('member_id', '=', member)
        .orderBy('id', 'desc')
        .limit(1)
        .executeTakeFirst();
      return row === undefined ? 0 : Number(row.read_through);
    },

    async markRead({ squad, member, seq }) {
      // Only moving on is kept: a read marker never goes back.
      await sql`
        insert into public.squad_chat_reads (squad_id, member_id, read_through)
        select ${squad}, ${member}, ${String(seq)}
        where coalesce((
          select read_through from public.squad_chat_reads
          where squad_id = ${squad} and member_id = ${member}
          order by id desc limit 1
        ), 0) < ${String(seq)}
      `.execute(db);
    },

    async unread({ squad, member, since, after }) {
      const row = await sql<{ count: string; mentions: string }>`
        select
          count(*) as count,
          count(*) filter (
            where ${member}::uuid = any (message.mentions)
              or replied.member_id = ${member}::uuid
          ) as mentions
        from public.squad_messages message
        left join public.squad_messages replied on replied.id = message.reply_to
        where message.squad_id = ${squad}
          and message.created_at >= ${since}
          and message.seq > ${String(after)}
          and message.member_id is distinct from ${member}::uuid
      `.execute(db);
      const [counts] = row.rows;
      return { count: Number(counts?.count ?? 0), mentions: Number(counts?.mentions ?? 0) };
    },
  };
}

function toMessage(
  row: Selectable<SquadMessages>,
  reactions: ChatMessage['reactions'],
): ChatMessage {
  return {
    id: MessageId.parse(row.id),
    seq: Number(row.seq),
    squad: SquadId.parse(row.squad_id),
    author:
      row.member_id === null
        ? { kind: 'coach', coach: row.coach_id ?? '' }
        : { kind: 'member', member: MemberId.parse(row.member_id) },
    kind: row.kind === 'note' ? 'note' : 'text',
    text: row.text,
    replyTo: row.reply_to === null ? undefined : MessageId.parse(row.reply_to),
    mentions: row.mentions.map((each) => MemberId.parse(each)),
    mentionsCoach: row.mentions_coach,
    at: new Date(row.created_at),
    reactions,
  };
}
