import type {
  ChatAlerts,
  ChatEmoji,
  ChatMessage,
  MemberId,
  MessageId,
  SquadId,
} from './domain/message.js';

/** A message to save: a member's, or the coach's (an answer or the day's 战术板 line). */
export type NewMessage =
  | {
      readonly id: MessageId;
      readonly squad: SquadId;
      readonly author: { readonly kind: 'member'; readonly member: MemberId };
      readonly text: string;
      readonly replyTo: MessageId | undefined;
      readonly mentions: readonly MemberId[];
      readonly mentionsCoach: boolean;
    }
  | {
      readonly squad: SquadId;
      readonly author: { readonly kind: 'coach'; readonly coach: string };
      /** The member's message it answers. */
      readonly replyTo: MessageId;
      readonly text: string;
    }
  | {
      readonly squad: SquadId;
      readonly author: { readonly kind: 'coach'; readonly coach: string };
      readonly noteDay: string;
      readonly text: string;
    };

/** Where squads' chats are kept. Messages are never changed; deleting one removes it. */
export interface ChatStore {
  /**
   * Saves a message, unless its id (a member's), the message it answers (the coach's) or its day
   * (a 战术板 line) is saved already: then it gives the one saved, and `created` is false.
   */
  add(message: NewMessage): Promise<{ readonly message: ChatMessage; readonly created: boolean }>;
  /** A message of the squad, if it is there. */
  find(squad: SquadId, id: MessageId): Promise<ChatMessage | undefined>;
  /** The squad's messages sent from `since`, before `before` (a `seq`) when given, newest first. */
  page(query: {
    readonly squad: SquadId;
    readonly since: Date;
    readonly before: number | undefined;
    readonly limit: number;
  }): Promise<ChatMessage[]>;
  /** The message with this `seq`, in that squad, if it is there. */
  bySeq(squad: SquadId, seq: number): Promise<ChatMessage | undefined>;
  /** Deletes a message. */
  remove(id: MessageId): Promise<void>;
  /** Sets the member's reaction on a message, or takes it off (`undefined`). */
  react(input: {
    readonly message: MessageId;
    readonly member: MemberId;
    readonly emoji: ChatEmoji | undefined;
  }): Promise<void>;
  /** Records a member's report of a message, once. */
  report(input: { readonly message: ChatMessage; readonly member: MemberId }): Promise<void>;
  /** Each of these members' alerts in the squad, for those who set them. */
  alerts(squad: SquadId, members: readonly MemberId[]): Promise<ReadonlyMap<MemberId, ChatAlerts>>;
  /** Saves a member's alerts in the squad, unless they are the alerts already. */
  setAlerts(input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly alerts: ChatAlerts;
  }): Promise<void>;
  /** How far the member read the squad's chat (a `seq`), 0 before they read any. */
  readThrough(squad: SquadId, member: MemberId): Promise<number>;
  /** Moves how far the member read on to `seq`, never back. */
  markRead(input: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly seq: number;
  }): Promise<void>;
  /**
   * Of the squad's messages sent from `since` after `after` (a `seq`) and not by `member`: how
   * many, and how many of them @ `member` or reply to them.
   */
  unread(query: {
    readonly squad: SquadId;
    readonly member: MemberId;
    readonly since: Date;
    readonly after: number;
  }): Promise<{ readonly count: number; readonly mentions: number }>;
}

/** Who is in which squad and since when. The squads module keeps that; the chat only asks. */
export interface ChatMembership {
  /** When `member` joined `squad`, or `undefined` while they aren't in it. */
  joinedAt(input: {
    readonly squad: SquadId;
    readonly member: MemberId;
  }): Promise<Date | undefined>;
  /** The squad's members now, the earliest to join first. */
  membersOf(squad: SquadId): Promise<readonly MemberId[]>;
}
