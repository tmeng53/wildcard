import {
  DEFAULT_ALERTS,
  pushedTo,
  type ChatAlerts,
  type ChatEmoji,
  type ChatMessage,
  type MemberId,
  type MessageId,
  type MessageText,
  type SquadId,
} from '../domain/message.js';
import {
  ChatMessageNotFoundError,
  MessageIdTakenError,
  NotYourMessageError,
  OwnMessageReportError,
  SquadNotJoinedError,
} from '../errors.js';
import type { ChatMembership, ChatStore } from '../ports.js';

/** The most messages one page holds. */
export const PAGE_LIMIT = 50;

/** A page of a squad's chat as a member reads it. */
export interface ChatPage {
  /** Newest first. */
  readonly messages: readonly ChatMessage[];
  /**
   * The messages these reply to that aren't on the page but the member can see, so the app can
   * show what each one replies to.
   */
  readonly quoted: readonly ChatMessage[];
  /** Whether older messages the member can see come before these. */
  readonly more: boolean;
  /** How far the member has read (a `seq`). */
  readonly readThrough: number;
  readonly alerts: ChatAlerts;
}

/** A message just sent, with the one it replies to, when it does. */
export interface SentMessage {
  readonly message: ChatMessage;
  readonly repliedTo: ChatMessage | undefined;
  /** False for a retry of a message saved already. */
  readonly created: boolean;
}

export interface SquadChat {
  /**
   * A page of the squad's chat for a member, newest first, from when they joined: the newest,
   * or those before `before` (a `seq`). Throws `SquadNotJoinedError` when they aren't in it.
   */
  page(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly before?: number;
    readonly limit: number;
  }): Promise<ChatPage>;
  /**
   * Sends a member's message. Its id is the app's, so a retry with the same words saves it once
   * (`created` false); other words under that id throw `MessageIdTakenError`. It may reply to a
   * message the member can see (else `ChatMessageNotFoundError`), and @ squadmates (anyone else
   * named is left out) and the coach.
   */
  send(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly id: MessageId;
    readonly text: MessageText;
    readonly replyTo?: MessageId;
    readonly mentions: readonly MemberId[];
    readonly mentionsCoach: boolean;
  }): Promise<SentMessage>;
  /** Deletes the member's own message: `NotYourMessageError` for anyone else's. */
  remove(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly message: MessageId;
  }): Promise<void>;
  /** Sets the member's one reaction on a message they can see, or takes it off. */
  react(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly message: MessageId;
    readonly emoji: ChatEmoji | undefined;
  }): Promise<ChatMessage>;
  /** Reports someone else's message to the admins, once however often it is sent. */
  report(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly message: MessageId;
  }): Promise<void>;
  /** The member's alerts in the squad. */
  alerts(input: { readonly member: MemberId; readonly squad: SquadId }): Promise<ChatAlerts>;
  setAlerts(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly alerts: ChatAlerts;
  }): Promise<void>;
  /** Marks the squad's chat read through `seq`; never moves back. */
  markRead(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly seq: number;
  }): Promise<void>;
  /** How many messages the member hasn't read, and how many of those @ them or reply to them. */
  unread(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
  }): Promise<{ readonly count: number; readonly mentions: number }>;
  /**
   * The message with this `seq` as the member sees it, with the one it replies to: `undefined`
   * when it is gone, or they can't see it (they left, or it came before they joined).
   */
  seen(input: {
    readonly member: MemberId;
    readonly squad: SquadId;
    readonly seq: number;
  }): Promise<
    { readonly message: ChatMessage; readonly quoted: ChatMessage | undefined } | undefined
  >;
  /** A message of the squad, whoever can see it, for the server's own flows. */
  find(squad: SquadId, id: MessageId): Promise<ChatMessage | undefined>;
  /** The squad's last `limit` messages up to and with `upTo` (a `seq`), oldest first. */
  recent(input: {
    readonly squad: SquadId;
    readonly upTo: number;
    readonly limit: number;
  }): Promise<readonly ChatMessage[]>;
  /** Saves the coach's answer to a member's message, once a message. */
  coachAnswer(input: {
    readonly squad: SquadId;
    readonly coach: string;
    readonly replyTo: MessageId;
    readonly text: string;
  }): Promise<{ readonly message: ChatMessage; readonly created: boolean }>;
  /** Posts the coach's 战术板 line of a day in the chat, once a day. */
  coachNote(input: {
    readonly squad: SquadId;
    readonly coach: string;
    readonly day: string;
    readonly text: string;
  }): Promise<{ readonly message: ChatMessage; readonly created: boolean }>;
  /** Whom a new message is pushed to, by their alerts, and whether it @s or replies to each. */
  pushTargets(
    sent: Pick<SentMessage, 'message' | 'repliedTo'>,
  ): Promise<readonly { readonly member: MemberId; readonly mentioned: boolean }[]>;
}

export function createSquadChat(deps: {
  readonly store: ChatStore;
  readonly membership: ChatMembership;
}): SquadChat {
  /** When the member joined the squad; throws while they aren't in it. */
  async function joined(squad: SquadId, member: MemberId): Promise<Date> {
    const at = await deps.membership.joinedAt({ squad, member });
    if (at === undefined) throw new SquadNotJoinedError(squad);
    return at;
  }

  /** A message of the squad the member can see: from when they joined. */
  async function visible({
    squad,
    id,
    since,
  }: {
    readonly squad: SquadId;
    readonly id: MessageId;
    readonly since: Date;
  }): Promise<ChatMessage> {
    const message = await deps.store.find(squad, id);
    if (message === undefined || message.at < since) throw new ChatMessageNotFoundError(id);
    return message;
  }

  return {
    async page({ member, squad, before, limit }) {
      const since = await joined(squad, member);
      const rows = await deps.store.page({ squad, since, before, limit: limit + 1 });
      const messages = rows.slice(0, limit);
      const onPage = new Set(messages.map(({ id }) => id));
      const missing = [
        ...new Set(
          messages.flatMap(({ replyTo }) =>
            replyTo === undefined || onPage.has(replyTo) ? [] : [replyTo],
          ),
        ),
      ];
      const quoted = (await Promise.all(missing.map((id) => deps.store.find(squad, id)))).filter(
        (each): each is ChatMessage => each !== undefined && each.at >= since,
      );
      const [readThrough, alerts] = await Promise.all([
        deps.store.readThrough(squad, member),
        deps.store.alerts(squad, [member]),
      ]);
      return {
        messages,
        quoted,
        more: rows.length > limit,
        readThrough,
        alerts: alerts.get(member) ?? DEFAULT_ALERTS,
      };
    },

    async send({ member, squad, id, text, replyTo, mentions, mentionsCoach }) {
      const since = await joined(squad, member);
      const repliedTo =
        replyTo === undefined ? undefined : await visible({ squad, id: replyTo, since });
      const squadmates = new Set(await deps.membership.membersOf(squad));
      const named = [...new Set(mentions)].filter(
        (each) => each !== member && squadmates.has(each),
      );
      const { message, created } = await deps.store.add({
        id,
        squad,
        author: { kind: 'member', member },
        text,
        replyTo,
        mentions: named,
        mentionsCoach,
      });
      // The id is the app's: a retry finds what the first try saved, which must be the same.
      if (
        !created &&
        (message.squad !== squad ||
          message.text !== text ||
          message.author.kind !== 'member' ||
          message.author.member !== member)
      ) {
        throw new MessageIdTakenError(id);
      }
      return { message, repliedTo, created };
    },

    async remove({ member, squad, message: id }) {
      const since = await joined(squad, member);
      const message = await visible({ squad, id, since });
      if (message.author.kind !== 'member' || message.author.member !== member) {
        throw new NotYourMessageError(id);
      }
      await deps.store.remove(id);
    },

    async react({ member, squad, message: id, emoji }) {
      const since = await joined(squad, member);
      await visible({ squad, id, since });
      await deps.store.react({ message: id, member, emoji });
      return visible({ squad, id, since });
    },

    async report({ member, squad, message: id }) {
      const since = await joined(squad, member);
      const message = await visible({ squad, id, since });
      if (message.author.kind === 'member' && message.author.member === member) {
        throw new OwnMessageReportError();
      }
      await deps.store.report({ message, member });
    },

    async alerts({ member, squad }) {
      await joined(squad, member);
      return (await deps.store.alerts(squad, [member])).get(member) ?? DEFAULT_ALERTS;
    },

    async setAlerts({ member, squad, alerts }) {
      await joined(squad, member);
      await deps.store.setAlerts({ squad, member, alerts });
    },

    async markRead({ member, squad, seq }) {
      await joined(squad, member);
      await deps.store.markRead({ squad, member, seq });
    },

    async unread({ member, squad }) {
      const since = await joined(squad, member);
      const after = await deps.store.readThrough(squad, member);
      return deps.store.unread({ squad, member, since, after });
    },

    async seen({ member, squad, seq }) {
      const since = await deps.membership.joinedAt({ squad, member });
      if (since === undefined) return undefined;
      const message = await deps.store.bySeq(squad, seq);
      if (message === undefined || message.at < since) return undefined;
      const quoted =
        message.replyTo === undefined ? undefined : await deps.store.find(squad, message.replyTo);
      return { message, quoted: quoted !== undefined && quoted.at >= since ? quoted : undefined };
    },

    find: (squad, id) => deps.store.find(squad, id),

    async recent({ squad, upTo, limit }) {
      const rows = await deps.store.page({ squad, since: new Date(0), before: upTo + 1, limit });
      return rows.toReversed();
    },

    coachAnswer: ({ squad, coach, replyTo, text }) =>
      deps.store.add({ squad, author: { kind: 'coach', coach }, replyTo, text }),

    coachNote: ({ squad, coach, day, text }) =>
      deps.store.add({ squad, author: { kind: 'coach', coach }, noteDay: day, text }),

    async pushTargets({ message, repliedTo }) {
      const members = await deps.membership.membersOf(message.squad);
      const alertsOf = await deps.store.alerts(message.squad, members);
      const repliedToMember =
        repliedTo?.author.kind === 'member' ? repliedTo.author.member : undefined;
      return pushedTo({ message, repliedTo: repliedToMember, members, alertsOf });
    },
  };
}
