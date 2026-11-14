import {
  MemberId,
  MessageId,
  MessageValue,
  cardsOf,
  isRunning,
  type CoachMessages,
  type Message,
} from '@wildcard/coach-messages';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// 教练消息卡 (Tracy, 2026-11-12): cards admins put on members' coach pages, said by the squad's
// coach with no model writing them. One template, filled by data, its buttons' steps too.

interface CoachMessageToolDependencies {
  readonly messages: CoachMessages;
  readonly clock: () => Date;
}

const shown = (message: Message, now: Date) => ({
  id: message.id,
  ...message.value,
  running: isRunning(message.value, now),
  by: message.by,
  savedAt: message.savedAt.toISOString(),
});

/** `list_coach_messages`: every coach message as it is now. */
export function listCoachMessages({ messages, clock }: CoachMessageToolDependencies) {
  return adminTool({
    name: 'list_coach_messages',
    title: 'List the coach messages',
    description:
      'Shows every coach message (教练消息卡) as it says now, the latest saved first, with ' +
      'whether it is running (members who open the coach page now get it).',
    changes: false,
    input: z.strictObject({}),
    run: async () => {
      const now = clock();
      return { version: 1, messages: (await messages.list()).map((each) => shown(each, now)) };
    },
  });
}

/** `put_coach_message`: writes a coach message, or changes one. */
export function putCoachMessage({ messages, clock }: CoachMessageToolDependencies) {
  return adminTool({
    name: 'put_coach_message',
    title: 'Write or change a coach message',
    description:
      'Writes a coach message (教练消息卡), or changes the one with this id: a card on the ' +
      'coach page, said by the squad’s coach (no model writes it), that each member whose squad ' +
      'has a coach gets once, on their first open of the coach page from startsAt until endsAt. ' +
      'Nothing is sent before startsAt, and squads without a coach get nothing. The card is one ' +
      'template: only `line` is needed, and each other slot shows only when filled. Words are ' +
      'in Simplified Chinese, English and Traditional Chinese. Each button’s `tap` is its steps ' +
      'in order: `open` a page in the app by its address (list_app_routes) or an https page, ' +
      '`feedback` (send the box’s words as 意见反馈), `close` (fold the card to its `thanks`) ' +
      'or `next` (turn into another card, up to three cards deep). Every tap, star and typed ' +
      'line is kept (get_coach_message_answers). A change shows to members who got it already; ' +
      'they never get it again, so a new question needs a new id. Name members to try it on ' +
      'yourselves first. Returns the message now, and whether this save changed it.',
    changes: true,
    input: z.strictObject({
      id: MessageId.describe('A short slug of your choosing, such as `enjoying-wildcard`.'),
      message: MessageValue,
    }),
    run: async ({ id, message }, { admin }) => {
      const saved = await messages.put({ id, value: message, by: MemberId.parse(admin) });
      return { version: 1, changed: saved.changed, message: shown(saved.message, clock()) };
    },
  });
}

/** `get_coach_message_answers`: what members did on a message's cards. */
export function getCoachMessageAnswers({ messages }: CoachMessageToolDependencies) {
  return adminTool({
    name: 'get_coach_message_answers',
    title: 'Read the answers to a coach message',
    description:
      'Shows what members did on each card of a coach message (by its path: `` for the first ' +
      'card, a follow-up by the button ids tapped to reach it, such as `no`): how many tapped ' +
      'each button, the stars given and their average, and every line typed, oldest first, ' +
      'each by member id.',
    changes: false,
    input: z.strictObject({ id: MessageId }),
    run: async ({ id }) => {
      const [message] = (await messages.list()).filter((each) => each.id === id);
      const rows = await messages.answersTo(id);
      const paths = message === undefined ? [] : [...cardsOf(message.value.card).keys()];
      for (const row of rows) if (!paths.includes(row.path)) paths.push(row.path);
      return {
        version: 1,
        id,
        cards: paths.map((path) => {
          const here = rows.filter((row) => row.path === path);
          // A Map, so a button named like an Object property (`constructor`) counts from 0.
          const taps = new Map<string, number>();
          const stars: number[] = [];
          const texts: { member: string; text: string; at: string }[] = [];
          for (const row of here) {
            if (row.part === 'tap') taps.set(row.button, (taps.get(row.button) ?? 0) + 1);
            if (row.part === 'stars') stars.push(row.stars);
            if (row.part === 'text') {
              texts.push({ member: row.member, text: row.text, at: row.at.toISOString() });
            }
          }
          return {
            path,
            taps: Object.fromEntries(taps),
            stars: {
              count: stars.length,
              ...(stars.length === 0
                ? {}
                : { average: stars.reduce((sum, each) => sum + each, 0) / stars.length }),
            },
            texts,
          };
        }),
      };
    },
  });
}

export const coachMessageTools = (deps: CoachMessageToolDependencies) => [
  listCoachMessages(deps),
  putCoachMessage(deps),
  getCoachMessageAnswers(deps),
];
