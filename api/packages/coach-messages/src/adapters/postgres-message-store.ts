import { isDeepStrictEqual } from 'node:util';

import type { Kysely } from 'kysely';

import {
  ButtonId,
  CardPath,
  MemberId,
  MessageId,
  MessageValue,
  SquadId,
  type AnswerPart,
  type Answered,
  type Message,
} from '../domain/message.js';
import type { AnswerRow, MessageStore } from '../ports.js';
import type { DB } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type CoachMessageTables = DB;

/** The message store on Postgres (`supabase/migrations`): every save a row, the newest wins. */
export function createPostgresMessageStore(db: Kysely<CoachMessageTables>): MessageStore {
  const current = () =>
    db
      .selectFrom('coach_messages')
      .select(['message_id', 'message', 'changed_by', 'at', 'id'])
      .distinctOn('message_id')
      .orderBy('message_id')
      .orderBy('id', 'desc');
  const read = (row: {
    readonly message_id: string;
    readonly message: unknown;
    readonly changed_by: string | null;
    readonly at: Date | string;
  }): Message[] => {
    // A shape this build no longer reads is left out, never an error.
    const value = MessageValue.safeParse(row.message);
    if (!value.success) return [];
    return [
      {
        id: MessageId.parse(row.message_id),
        value: value.data,
        by: row.changed_by,
        savedAt: new Date(row.at),
      },
    ];
  };
  const byId = async (ids: readonly MessageId[]) => {
    if (ids.length === 0) return [];
    const rows = await current()
      .where('message_id', 'in', [...new Set(ids)])
      .execute();
    return rows.flatMap(read);
  };
  return {
    async put({ id, value, by }) {
      const [now] = await byId([id]);
      if (now !== undefined && isDeepStrictEqual(now.value, value)) return { changed: false };
      await db
        .insertInto('coach_messages')
        .values({ message_id: id, message: JSON.stringify(value), changed_by: by })
        .execute();
      return { changed: true };
    },

    async all() {
      const rows = await db
        .selectFrom(current().as('current'))
        .selectAll()
        .orderBy('id', 'desc')
        .execute();
      return rows.flatMap(read);
    },

    byId,

    async deliver({ member, squad, coach, messages, at }) {
      if (messages.length === 0) return;
      await db
        .insertInto('coach_message_deliveries')
        .values(
          [...new Set(messages)].map((message) => ({
            member_id: member,
            message_id: message,
            squad_id: squad,
            coach_id: coach,
            at,
          })),
        )
        .onConflict((conflict) => conflict.columns(['member_id', 'message_id']).doNothing())
        .execute();
    },

    async deliveries(member) {
      const rows = await db
        .selectFrom('coach_message_deliveries')
        .select(['message_id', 'squad_id', 'coach_id', 'at'])
        .where('member_id', '=', member)
        .orderBy('at')
        .orderBy('message_id')
        .execute();
      return rows.map((row) => ({
        message: MessageId.parse(row.message_id),
        squad: SquadId.parse(row.squad_id),
        coach: row.coach_id,
        at: new Date(row.at),
      }));
    },

    async answer({ member, message, path, part, at }) {
      const inserted = await db
        .insertInto('coach_message_answers')
        .values({
          member_id: member,
          message_id: message,
          path,
          part: part.part,
          button: part.part === 'tap' ? part.button : null,
          stars: part.part === 'stars' ? part.stars : null,
          text: part.part === 'text' ? part.text : null,
          at,
        })
        .onConflict((conflict) =>
          conflict.columns(['member_id', 'message_id', 'path', 'part']).doNothing(),
        )
        .returning('id')
        .executeTakeFirst();
      return { fresh: inserted !== undefined };
    },

    async answersOf(member, messages) {
      const answered = new Map<MessageId, Map<CardPath, Answered>>();
      if (messages.length === 0) return answered;
      const rows = await selectAnswers()
        .where('member_id', '=', member)
        .where('message_id', 'in', [...new Set(messages)])
        .execute();
      for (const row of rows) {
        const part = partOf(row);
        const path = CardPath.safeParse(row.path);
        if (part === undefined || !path.success) continue;
        const id = MessageId.parse(row.message_id);
        const cards = answered.get(id) ?? new Map<CardPath, Answered>();
        cards.set(path.data, { ...cards.get(path.data), ...fieldOf(part) });
        answered.set(id, cards);
      }
      return answered;
    },

    async answersTo(message) {
      const rows = await selectAnswers().where('message_id', '=', message).execute();
      return rows.flatMap((row): AnswerRow[] => {
        const part = partOf(row);
        const path = CardPath.safeParse(row.path);
        return part === undefined || !path.success
          ? []
          : [
              {
                ...part,
                member: MemberId.parse(row.member_id),
                path: path.data,
                at: new Date(row.at),
              },
            ];
      });
    },
  };

  function selectAnswers() {
    return db
      .selectFrom('coach_message_answers')
      .select(['member_id', 'message_id', 'path', 'part', 'button', 'stars', 'text', 'at'])
      .orderBy('at')
      .orderBy('id');
  }
}

function partOf(row: {
  readonly part: string;
  readonly button: string | null;
  readonly stars: number | null;
  readonly text: string | null;
}): AnswerPart | undefined {
  if (row.part === 'tap' && row.button !== null) {
    return { part: 'tap', button: ButtonId.parse(row.button) };
  }
  if (row.part === 'stars' && row.stars !== null) return { part: 'stars', stars: row.stars };
  if (row.part === 'text' && row.text !== null) return { part: 'text', text: row.text };
  return undefined;
}

function fieldOf(part: AnswerPart): Answered {
  switch (part.part) {
    case 'tap':
      return { tap: part.button };
    case 'stars':
      return { stars: part.stars };
    case 'text':
      return { text: part.text };
  }
}
