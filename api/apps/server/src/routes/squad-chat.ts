import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import {
  ChatAlerts,
  ChatEmoji,
  MemberId,
  MessageId,
  MessageText,
  PAGE_LIMIT,
  SquadId,
  asksCoach,
  type ChatMessage as ChatMessageRecord,
  type SquadChat,
} from '@wildcard/squad-chat';

import { bodyVersion } from '../body-version.js';
import { answerInChat, type ChatCoachAnswerer } from '../flows/coach-answer.js';
import { pushChatMessage, type ChatPushDependencies } from '../flows/chat-push.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const messageFields = {
  id: MessageId.meta({ description: 'The message’s id: the app picks a member’s.' }),
  seq: z
    .int()
    .positive()
    .meta({
      description:
        'Its place in the squad’s chat, oldest first: what pages, `PUT …/chat/read` and the ' +
        'live `chat` event go by.',
    }),
  member: z.uuid().optional().meta({ description: 'Who wrote it, for a member’s message.' }),
  coachId: z.string().optional().meta({
    description: 'The coach who wrote it, by id, for the coach’s (with the 教练 tag).',
    example: 'xiaohun',
  }),
  kind: z.enum(['text', 'note']).meta({
    description:
      '`text` is written; `note` is the coach’s 战术板 line of the day, shown as its card. ' +
      'Skip a kind you don’t know.',
  }),
  text: z.string().meta({ description: 'What it says.' }),
  replyTo: z.uuid().optional().meta({
    description: 'The message it replies to, while that one is there.',
  }),
  mentions: z.array(z.uuid()).meta({ description: 'The squadmates it @s.' }),
  mentionsCoach: z.boolean().meta({ description: 'Whether it @s the coach.' }),
  at: z.iso.datetime().meta({ description: 'When it was sent, in UTC with milliseconds.' }),
  reactions: z
    .array(z.strictObject({ member: z.uuid(), emoji: z.string() }))
    .meta({ description: 'Members’ reactions, one each, the earliest first.' }),
};

export const ChatMessage = z
  .strictObject({ version: bodyVersion(1), ...messageFields })
  .openapi('ChatMessage');

export const ChatMessageDraft = z
  .strictObject({
    version: bodyVersion(1),
    text: MessageText,
    replyTo: MessageId.optional().meta({
      description: 'The message it replies to: one the caller can see in this chat.',
    }),
    mentions: z.array(z.uuid()).max(8).default([]).meta({
      description: 'The squadmates it @s; anyone not in the squad is left out.',
    }),
    mentionsCoach: z.boolean().default(false).meta({
      description: 'Whether it @s the coach, who then answers (as it does a reply to it).',
    }),
  })
  .openapi('ChatMessageDraft');

export const ChatPage = z
  .strictObject({
    version: bodyVersion(1),
    messages: z.array(ChatMessage).meta({ description: 'Newest first.' }),
    quoted: z.array(ChatMessage).meta({
      description:
        'The messages those reply to that aren’t among them, so each reply can show what it ' +
        'replies to.',
    }),
    more: z.boolean().meta({ description: 'Whether older messages come before these.' }),
    readThrough: z.int().nonnegative().meta({
      description: 'How far the caller read (a `seq`), 0 before they read any.',
    }),
    alerts: ChatAlerts.meta({ description: 'The caller’s alerts in this squad.' }),
  })
  .openapi('ChatPage');

export const ChatAlertSettings = z
  .strictObject({
    version: bodyVersion(1),
    alerts: ChatAlerts.meta({
      description:
        'When the caller gets a push for this squad’s messages: `mentions` (an @ or a reply to ' +
        'them, the default), `all` or `none`.',
    }),
  })
  .openapi('ChatAlertSettings');

export const ChatReaction = z
  .strictObject({
    version: bodyVersion(1),
    emoji: ChatEmoji.meta({ description: 'Any one emoji.', example: '🔥' }),
  })
  .openapi('ChatReaction');

export const ChatRead = z
  .strictObject({
    version: bodyVersion(1),
    seq: z.int().positive().meta({ description: 'The newest message the caller has seen.' }),
  })
  .openapi('ChatRead');

export const ChatUnread = z
  .strictObject({
    version: bodyVersion(1),
    count: z.int().nonnegative().meta({ description: 'Messages the caller hasn’t read.' }),
    mentions: z.int().nonnegative().meta({
      description: 'Those of them that @ the caller or reply to them.',
    }),
  })
  .openapi('ChatUnread');

/** A message as the wire carries it. */
export function wireMessage(message: ChatMessageRecord): z.infer<typeof ChatMessage> {
  return {
    version: 1,
    id: message.id,
    seq: message.seq,
    ...(message.author.kind === 'member'
      ? { member: message.author.member }
      : { coachId: message.author.coach }),
    kind: message.kind,
    text: message.text,
    ...(message.replyTo === undefined ? {} : { replyTo: message.replyTo }),
    mentions: [...message.mentions],
    mentionsCoach: message.mentionsCoach,
    at: message.at.toISOString(),
    reactions: message.reactions.map(({ member, emoji }) => ({ member, emoji })),
  };
}

const squadParams = z.strictObject({ squadId: SquadId });
const messageParams = z.strictObject({ squadId: SquadId, messageId: MessageId });

const failures = {
  401: problem('No bearer token, or not a valid one'),
  403: problem('The caller isn’t in this squad (`SQUAD_NOT_JOINED`)'),
  503: problem('Sign-in can’t be checked right now'),
};

const notFound = {
  404: problem(
    'No such message the caller can see here: deleted, or sent before they joined ' +
      '(`CHAT_MESSAGE_NOT_FOUND`)',
  ),
};

/**
 * A squad's group chat (群聊): `/squads/{squadId}/chat/…`. New messages, reactions and deletions
 * reach the members' open apps as `GET /me/events` events.
 */
export function squadChat(
  deps: ChatPushDependencies & {
    readonly verifyToken: VerifyToken;
    readonly chat: SquadChat;
    /** Has the coach answer a message to it; left out, the coach never answers in the chat. */
    readonly chatCoachAnswer?: ChatCoachAnswerer | undefined;
  },
) {
  const security = [{ bearer: [] }];

  const page = createRoute({
    method: 'get',
    path: '/squads/{squadId}/chat/messages',
    operationId: 'listSquadChat',
    summary: 'A page of the squad’s chat (群聊)',
    description:
      'Newest first, only what was sent since the caller joined. Pass the oldest `seq` you have ' +
      'as `before` for the page before it.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      query: z.strictObject({
        before: z.coerce.number().int().positive().optional(),
        limit: z.coerce.number().int().min(1).max(PAGE_LIMIT).default(PAGE_LIMIT),
      }),
    },
    responses: {
      200: { description: 'The page', content: { 'application/json': { schema: ChatPage } } },
      400: problem('Not a valid squad id, `before` or `limit`'),
      ...failures,
    },
  });

  const write = createRoute({
    method: 'put',
    path: '/squads/{squadId}/chat/messages/{messageId}',
    operationId: 'sendChatMessage',
    summary: 'Send a message to the squad’s chat',
    description:
      'The app names the message, so the same one again changes nothing and is safe to repeat. ' +
      'Messages are never edited. The squad hears it at once (`GET /me/events`), and members are ' +
      'pushed by their alerts. A message that @s the coach, or replies to it, is answered soon ' +
      'after: members see the coach typing (`coachTyping`), then its message.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: messageParams,
      body: { required: true, content: { 'application/json': { schema: ChatMessageDraft } } },
    },
    responses: {
      200: {
        description: 'Sent already',
        content: { 'application/json': { schema: ChatMessage } },
      },
      201: { description: 'Sent', content: { 'application/json': { schema: ChatMessage } } },
      400: problem('Not a valid message'),
      409: problem('The id holds a different message (`MESSAGE_ID_TAKEN`)'),
      ...notFound,
      ...jsonBodyFailures,
      ...failures,
    },
  });

  const remove = createRoute({
    method: 'delete',
    path: '/squads/{squadId}/chat/messages/{messageId}',
    operationId: 'deleteChatMessage',
    summary: 'Delete your message',
    description: 'It is gone for everyone; a reply to it stays, without what it replied to.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: messageParams },
    responses: {
      204: { description: 'Deleted' },
      400: problem('Not a valid id'),
      ...notFound,
      ...failures,
      403: problem(
        'The caller isn’t in this squad (`SQUAD_NOT_JOINED`), or it isn’t theirs ' +
          '(`NOT_YOUR_MESSAGE`)',
      ),
    },
  });

  const react = createRoute({
    method: 'put',
    path: '/squads/{squadId}/chat/messages/{messageId}/reaction',
    operationId: 'reactToChatMessage',
    summary: 'React to a message',
    description: 'One emoji per member a message; another one takes its place.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: messageParams,
      body: { required: true, content: { 'application/json': { schema: ChatReaction } } },
    },
    responses: {
      200: {
        description: 'The message now',
        content: { 'application/json': { schema: ChatMessage } },
      },
      400: problem('Not one emoji'),
      ...notFound,
      ...jsonBodyFailures,
      ...failures,
    },
  });

  const unreact = createRoute({
    method: 'delete',
    path: '/squads/{squadId}/chat/messages/{messageId}/reaction',
    operationId: 'unreactToChatMessage',
    summary: 'Take your reaction off a message',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: messageParams },
    responses: {
      200: {
        description: 'The message now',
        content: { 'application/json': { schema: ChatMessage } },
      },
      400: problem('Not a valid id'),
      ...notFound,
      ...failures,
    },
  });

  const report = createRoute({
    method: 'post',
    path: '/squads/{squadId}/chat/messages/{messageId}/report',
    operationId: 'reportChatMessage',
    summary: 'Report someone’s message (举报)',
    description:
      'The admins see what it said even if it is deleted later. Reporting it again changes ' +
      'nothing.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: messageParams },
    responses: {
      204: { description: 'Reported' },
      400: problem('Not a valid id, or the caller’s own message (`OWN_MESSAGE`)'),
      ...notFound,
      ...failures,
    },
  });

  const getAlerts = createRoute({
    method: 'get',
    path: '/squads/{squadId}/chat/alerts',
    operationId: 'getChatAlerts',
    summary: 'When the caller gets a push for this squad’s chat',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      200: {
        description: 'The caller’s alerts',
        content: { 'application/json': { schema: ChatAlertSettings } },
      },
      400: problem('Not a valid squad id'),
      ...failures,
    },
  });

  const putAlerts = createRoute({
    method: 'put',
    path: '/squads/{squadId}/chat/alerts',
    operationId: 'setChatAlerts',
    summary: 'Change when the caller gets a push for this squad’s chat',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: ChatAlertSettings } } },
    },
    responses: {
      200: {
        description: 'Saved',
        content: { 'application/json': { schema: ChatAlertSettings } },
      },
      400: problem('Not valid alerts'),
      ...jsonBodyFailures,
      ...failures,
    },
  });

  const read = createRoute({
    method: 'put',
    path: '/squads/{squadId}/chat/read',
    operationId: 'markChatRead',
    summary: 'Mark the squad’s chat read up to a message',
    description: 'Never moves back, so a stale call is harmless.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      params: squadParams,
      body: { required: true, content: { 'application/json': { schema: ChatRead } } },
    },
    responses: {
      204: { description: 'Marked' },
      400: problem('Not a valid `seq`'),
      ...jsonBodyFailures,
      ...failures,
    },
  });

  const unread = createRoute({
    method: 'get',
    path: '/squads/{squadId}/chat/unread',
    operationId: 'getChatUnread',
    summary: 'How much of the squad’s chat the caller hasn’t read',
    description: 'The count on the chat’s button beside 打卡.',
    security,
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: squadParams },
    responses: {
      200: { description: 'The counts', content: { 'application/json': { schema: ChatUnread } } },
      400: problem('Not a valid squad id'),
      ...failures,
    },
  });

  const caller = (c: { var: SignedIn['Variables'] }) => MemberId.parse(c.var.caller.userId);

  return new OpenAPIHono<SignedIn>()
    .openapi(page, async (c) => {
      const { before, limit } = c.req.valid('query');
      const found = await deps.chat.page({
        member: caller(c),
        squad: c.req.valid('param').squadId,
        limit,
        ...(before === undefined ? {} : { before }),
      });
      return c.json(
        {
          version: 1 as const,
          messages: found.messages.map(wireMessage),
          quoted: found.quoted.map(wireMessage),
          more: found.more,
          readThrough: found.readThrough,
          alerts: found.alerts,
        },
        200,
      );
    })
    .openapi(write, async (c) => {
      const { squadId, messageId } = c.req.valid('param');
      const draft = c.req.valid('json');
      const sent = await deps.chat.send({
        member: caller(c),
        squad: squadId,
        id: messageId,
        text: draft.text,
        ...(draft.replyTo === undefined ? {} : { replyTo: draft.replyTo }),
        mentions: draft.mentions.map((each) => MemberId.parse(each)),
        mentionsCoach: draft.mentionsCoach,
      });
      // Sent before answering: Cloud Run gives the server CPU only while a request runs.
      if (sent.created) {
        await pushChatMessage(deps, sent);
        if (deps.chatCoachAnswer !== undefined && asksCoach(sent.message, sent.repliedTo?.author)) {
          await answerInChat(
            { answer: deps.chatCoachAnswer, log: deps.log },
            { squad: squadId, message: messageId },
          );
        }
      }
      const body = wireMessage(sent.message);
      return sent.created ? c.json(body, 201) : c.json(body, 200);
    })
    .openapi(remove, async (c) => {
      const { squadId, messageId } = c.req.valid('param');
      await deps.chat.remove({ member: caller(c), squad: squadId, message: messageId });
      return c.body(null, 204);
    })
    .openapi(react, async (c) => {
      const { squadId, messageId } = c.req.valid('param');
      const message = await deps.chat.react({
        member: caller(c),
        squad: squadId,
        message: messageId,
        emoji: c.req.valid('json').emoji,
      });
      return c.json(wireMessage(message), 200);
    })
    .openapi(unreact, async (c) => {
      const { squadId, messageId } = c.req.valid('param');
      const message = await deps.chat.react({
        member: caller(c),
        squad: squadId,
        message: messageId,
        emoji: undefined,
      });
      return c.json(wireMessage(message), 200);
    })
    .openapi(report, async (c) => {
      const { squadId, messageId } = c.req.valid('param');
      await deps.chat.report({ member: caller(c), squad: squadId, message: messageId });
      return c.body(null, 204);
    })
    .openapi(getAlerts, async (c) => {
      const alerts = await deps.chat.alerts({
        member: caller(c),
        squad: c.req.valid('param').squadId,
      });
      return c.json({ version: 1 as const, alerts }, 200);
    })
    .openapi(putAlerts, async (c) => {
      const { alerts } = c.req.valid('json');
      await deps.chat.setAlerts({ member: caller(c), squad: c.req.valid('param').squadId, alerts });
      return c.json({ version: 1 as const, alerts }, 200);
    })
    .openapi(read, async (c) => {
      await deps.chat.markRead({
        member: caller(c),
        squad: c.req.valid('param').squadId,
        seq: c.req.valid('json').seq,
      });
      return c.body(null, 204);
    })
    .openapi(unread, async (c) => {
      const counts = await deps.chat.unread({
        member: caller(c),
        squad: c.req.valid('param').squadId,
      });
      return c.json({ version: 1 as const, ...counts }, 200);
    });
}
