import { MemberId as ProfileMember, type Members } from '@wildcard/members';
import { MemberId as PushMember, type Push, type PushNotification } from '@wildcard/push';
import type { ChatMessage, SentMessage, SquadChat } from '@wildcard/squad-chat';

import { setTimeout as wait } from 'node:timers/promises';

import type { Log } from '../log.js';
import { pushAlert } from '../push-copy.js';

/** How long a message's answer waits for its pushes; slower ones go on, and the message answers. */
const PUSH_WAIT_MS = 3000;

export interface ChatPushDependencies {
  readonly chat: Pick<SquadChat, 'pushTargets'>;
  readonly members: Pick<Members, 'squadmates'>;
  readonly push: Pick<Push, 'settingsOf' | 'notifyMembers'>;
  /** The coaches' names now, for a coach's message. */
  readonly coachNames: () => Promise<ReadonlyMap<string, string>>;
  readonly log: Log;
}

/**
 * Pushes a new chat message to the squad's members by each one's alerts in that squad (an @ or a
 * reply to them by default, every message, or none), and only to those who keep push on (the
 * app's 通知 switch). Never its writer. Never throws, and waits at most `PUSH_WAIT_MS`: a
 * message is sent whether or not anyone hears of it by push.
 */
export async function pushChatMessage(
  deps: ChatPushDependencies,
  sent: Pick<SentMessage, 'message' | 'repliedTo'>,
): Promise<void> {
  const stop = new AbortController();
  const late = wait(PUSH_WAIT_MS, 'late' as const, { signal: stop.signal }).catch(() => undefined);
  const outcome = await Promise.race([send(deps, sent), late]);
  stop.abort();
  if (outcome === 'late') deps.log.warn('chat push still sending', { message: sent.message.id });
}

async function send(
  deps: ChatPushDependencies,
  sent: Pick<SentMessage, 'message' | 'repliedTo'>,
): Promise<void> {
  try {
    const targets = await deps.chat.pushTargets(sent);
    if (targets.length === 0) return;
    const name = await writerName(deps, sent.message);
    // A member without a name yet is still mid-sign-up, and can't have written; say nothing.
    if (name === undefined) return;
    await Promise.all(
      targets.map(async ({ member, mentioned }) => {
        const to = PushMember.parse(member);
        if (!(await deps.push.settingsOf(to)).dailyProgress) return;
        const notification = chatNotification({ message: sent.message, name, mentioned });
        const outcome = await deps.push.notifyMembers({ members: [to], notification });
        if (outcome.failures.length > 0) {
          deps.log.warn('chat push not sent to every phone', {
            member,
            failures: outcome.failures,
          });
        }
      }),
    );
  } catch (error) {
    deps.log.error('chat push not sent', { message: sent.message.id, error });
  }
}

/** The writer's nickname, or the coach's name. */
async function writerName(
  deps: Pick<ChatPushDependencies, 'members' | 'coachNames'>,
  message: ChatMessage,
): Promise<string | undefined> {
  if (message.author.kind === 'coach') {
    return (await deps.coachNames()).get(message.author.coach);
  }
  const member = ProfileMember.parse(message.author.member);
  return (await deps.members.squadmates([member])).get(member)?.character?.nickname;
}

/**
 * The push of a chat message: a String Catalog key filled with the writer's name and the
 * message's words, 「小美：走起」, or 「小美@了你：走起」 when it @s or replies to the member. A
 * tap opens the squad's chat.
 */
export function chatNotification({
  message,
  name,
  mentioned,
}: {
  readonly message: Pick<ChatMessage, 'id' | 'squad' | 'text'>;
  readonly name: string;
  readonly mentioned: boolean;
}): PushNotification {
  return {
    alert: pushAlert(mentioned ? 'push.chat.mention' : 'push.chat', [name, message.text]),
    category: 'chat',
    thread: `chat-${message.squad}`,
    collapseId: `chat-${message.id}`,
    interruption: 'active',
    event: { kind: 'chat', squad: message.squad },
  };
}
