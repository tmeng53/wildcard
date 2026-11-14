import type {
  AnswerPart,
  Answered,
  CardPath,
  Message,
  MessageId,
  MessageValue,
  MemberId,
  SquadId,
} from './domain/message.js';

/** When a member first got a message, where and from which coach. */
export interface Delivery {
  readonly message: MessageId;
  readonly squad: SquadId;
  readonly coach: string;
  readonly at: Date;
}

/** One part of one member's answer, for the admin reading them. */
export type AnswerRow = AnswerPart & {
  readonly member: MemberId;
  readonly path: CardPath;
  readonly at: Date;
};

/** Where messages, who got them and their answers are kept; nothing is changed once written. */
export interface MessageStore {
  /** Saves `value` as what `id` says now, unless it says that already: then `changed` is false. */
  put(message: {
    readonly id: MessageId;
    readonly value: MessageValue;
    readonly by: MemberId;
  }): Promise<{ readonly changed: boolean }>;
  /** Every message as it is now, the latest saved first. */
  all(): Promise<Message[]>;
  /** These messages as they are now; one without a row is left out. */
  byId(ids: readonly MessageId[]): Promise<Message[]>;
  /** Keeps that `member` got each of `messages`; one got before keeps its first delivery. */
  deliver(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly coach: string;
    readonly messages: readonly MessageId[];
    readonly at: Date;
  }): Promise<void>;
  /** What `member` got, every squad, oldest first. */
  deliveries(member: MemberId): Promise<Delivery[]>;
  /** Keeps one part of an answer, unless that part was answered before: then `fresh` is false. */
  answer(input: {
    readonly member: MemberId;
    readonly message: MessageId;
    readonly path: CardPath;
    readonly part: AnswerPart;
    readonly at: Date;
  }): Promise<{ readonly fresh: boolean }>;
  /** `member`'s answers so far to each of `messages`, by card; one not answered is left out. */
  answersOf(
    member: MemberId,
    messages: readonly MessageId[],
  ): Promise<Map<MessageId, Map<CardPath, Answered>>>;
  /** Every part of every answer to `message`, oldest first. */
  answersTo(message: MessageId): Promise<AnswerRow[]>;
}
