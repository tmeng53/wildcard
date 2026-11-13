import {
  MessageId,
  TEXT_LIMIT,
  isFor,
  isRunning,
  refusal,
  type AnswerPart,
  type Answered,
  type CardPath,
  type MemberId,
  type Message,
  type MessageValue,
  type SquadId,
} from '../domain/message.js';
import { CoachMessageAnswerInvalidError, CoachMessageNotFoundError } from '../errors.js';
import type { AnswerRow, MessageStore } from '../ports.js';

/** A message as a member's card: when they got it, from which coach, and what they answered. */
export interface MessageCard {
  readonly id: MessageId;
  readonly value: MessageValue;
  readonly coach: string;
  readonly at: Date;
  readonly answered: ReadonlyMap<CardPath, Answered>;
}

export interface CoachMessages {
  /** Writes a message, or changes the one with its id. */
  put(input: {
    readonly id: MessageId;
    readonly value: MessageValue;
    readonly by: MemberId;
  }): Promise<{ readonly changed: boolean; readonly message: Message }>;
  /** Every message as it is now, the latest saved first. */
  list(): Promise<Message[]>;
  /**
   * The member's message cards in `squad`, giving them first each one running now that is for
   * them, from the squad's `coach` (none without one: a message is said by a coach).
   */
  cardsFor(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly coach: string | undefined;
  }): Promise<MessageCard[]>;
  /** Keeps one part of the member's answer on one card; the first answer to a part stands. */
  answer(input: {
    readonly member: MemberId;
    readonly message: MessageId;
    readonly path: CardPath;
    readonly part: AnswerPart;
  }): Promise<ReadonlyMap<CardPath, Answered>>;
  /** Every answer to `message`, oldest first. */
  answersTo(message: MessageId): Promise<AnswerRow[]>;
}

export function createCoachMessages(deps: {
  readonly store: MessageStore;
  readonly clock: () => Date;
}): CoachMessages {
  const { store, clock } = deps;
  const answersOf = async (member: MemberId, message: MessageId) =>
    (await store.answersOf(member, [message])).get(message) ?? new Map<CardPath, Answered>();
  return {
    async put({ id, value, by }) {
      const { changed } = await store.put({ id, value, by });
      const [message] = await store.byId([id]);
      if (message === undefined) throw new Error(`message ${id} was saved but can’t be read`);
      return { changed, message };
    },

    list: () => store.all(),

    async cardsFor({ member, squad, coach }) {
      const now = clock();
      if (coach !== undefined) {
        const got = new Set((await store.deliveries(member)).map((each) => each.message));
        const due = (await store.all()).filter(
          (message) =>
            !got.has(message.id) && isRunning(message.value, now) && isFor(message.value, member),
        );
        await store.deliver({
          member,
          squad,
          coach,
          messages: due.map((message) => message.id),
          at: now,
        });
      }
      const here = (await store.deliveries(member)).filter((each) => each.squad === squad);
      const ids = here.map((each) => each.message);
      const [messages, answers] = await Promise.all([
        store.byId(ids),
        store.answersOf(member, ids),
      ]);
      const byId = new Map(messages.map((message) => [message.id, message]));
      return here.flatMap((delivery): MessageCard[] => {
        const message = byId.get(delivery.message);
        return message === undefined
          ? []
          : [
              {
                id: message.id,
                value: message.value,
                coach: delivery.coach,
                at: delivery.at,
                answered: answers.get(message.id) ?? new Map(),
              },
            ];
      });
    },

    async answer({ member, message: id, path, part }) {
      const got = (await store.deliveries(member)).some((each) => each.message === id);
      const [message] = got ? await store.byId([id]) : [];
      if (message === undefined) throw new CoachMessageNotFoundError(id);
      const trimmed: AnswerPart =
        part.part === 'text' ? { part: 'text', text: part.text.trim().slice(0, TEXT_LIMIT) } : part;
      if (trimmed.part === 'text' && trimmed.text === '') {
        throw new CoachMessageAnswerInvalidError('nothing was typed');
      }
      const why = refusal(message.value, {
        answered: await answersOf(member, id),
        path,
        part: trimmed,
      });
      if (why !== undefined) throw new CoachMessageAnswerInvalidError(why);
      await store.answer({ member, message: id, path, part: trimmed, at: clock() });
      return answersOf(member, id);
    },

    answersTo: (message) => store.answersTo(MessageId.parse(message)),
  };
}
