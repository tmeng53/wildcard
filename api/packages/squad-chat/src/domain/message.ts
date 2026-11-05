import { isOneEmoji, typedText } from '@wildcard/typed-text';
import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

/** A message's id: the app names a member's, so a retry saves it once. */
export const MessageId = z.uuid().brand<'MessageId'>();
export type MessageId = z.infer<typeof MessageId>;

/** The most characters a member's message holds. */
export const MESSAGE_MAX_CHARACTERS = 500;

/** A member's message: trimmed, 1 to 500 characters, and it may span lines. */
export const MessageText = typedText({
  max: MESSAGE_MAX_CHARACTERS,
  oneLine: false,
  description: 'Trimmed, then 1 to 500 characters as people see them; may span lines.',
});
export type MessageText = z.infer<typeof MessageText>;

/** A reaction on a message: any one emoji, as on 动态. */
export const ChatEmoji = z.string().refine(isOneEmoji, 'Not one emoji').brand<'ChatEmoji'>();
export type ChatEmoji = z.infer<typeof ChatEmoji>;

/**
 * How a member is told of a squad's messages by push: when someone @s them or replies to them
 * (`mentions`, the default), for every message (`all`), or never (`none`).
 */
export const ChatAlerts = z.enum(['mentions', 'all', 'none']);
export type ChatAlerts = z.infer<typeof ChatAlerts>;

export const DEFAULT_ALERTS: ChatAlerts = 'mentions';

/** Who wrote a message: a member, or the squad's coach (by its id in the coaches). */
export type Author =
  | { readonly kind: 'member'; readonly member: MemberId }
  | { readonly kind: 'coach'; readonly coach: string };

/** A message in a squad's chat, as it is kept. */
export interface ChatMessage {
  readonly id: MessageId;
  /** Its place in the squad's chat, oldest first. */
  readonly seq: number;
  readonly squad: SquadId;
  readonly author: Author;
  /** `text` is written; `note` is the coach's 战术板 line of the day. */
  readonly kind: 'text' | 'note';
  readonly text: string;
  /** The message it replies to, while that one is there. */
  readonly replyTo: MessageId | undefined;
  /** The members it @s, in the order written. */
  readonly mentions: readonly MemberId[];
  /** Whether it @s the coach. */
  readonly mentionsCoach: boolean;
  readonly at: Date;
  /** Members' reactions, the earliest first. */
  readonly reactions: readonly { readonly member: MemberId; readonly emoji: ChatEmoji }[];
}

/**
 * Whom a new message should be pushed to, by each member's alerts: everyone with `all`, and
 * those it @s or whose message it replies to unless they chose `none`. Never its writer.
 */
export function pushedTo({
  message,
  repliedTo,
  members,
  alertsOf,
}: {
  readonly message: ChatMessage;
  /** Who wrote the message it replies to, when a member did. */
  readonly repliedTo: MemberId | undefined;
  /** The squad's members now. */
  readonly members: readonly MemberId[];
  readonly alertsOf: ReadonlyMap<MemberId, ChatAlerts>;
}): { readonly member: MemberId; readonly mentioned: boolean }[] {
  const writer = message.author.kind === 'member' ? message.author.member : undefined;
  return members.flatMap((member) => {
    if (member === writer) return [];
    const alerts = alertsOf.get(member) ?? DEFAULT_ALERTS;
    const mentioned = message.mentions.includes(member) || repliedTo === member;
    if (alerts === 'none' || (alerts === 'mentions' && !mentioned)) return [];
    return [{ member, mentioned }];
  });
}

/** Whether a member's message asks the coach for an answer: it @s the coach, or replies to it. */
export function asksCoach(
  message: Pick<ChatMessage, 'author' | 'mentionsCoach'>,
  repliedTo: Author | undefined,
): boolean {
  if (message.author.kind !== 'member') return false;
  return message.mentionsCoach || repliedTo?.kind === 'coach';
}
