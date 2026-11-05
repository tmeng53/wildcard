import type { SquadChat } from '@wildcard/squad-chat';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

/** `list_chat_reports`: what members reported in their squads' chats (举报), newest first. */
export function listChatReports(deps: { readonly chat: Pick<SquadChat, 'reports'> }) {
  return adminTool({
    name: 'list_chat_reports',
    title: 'List reported chat messages',
    description:
      'Lists the messages members reported in their squads’ chats, newest first: when, the ' +
      'squad, the message (none once it was deleted), who wrote it (none for the coach’s), ' +
      'what it said when reported, and who reported it.',
    changes: false,
    input: z.strictObject({
      limit: z.int().min(1).max(200).default(50).describe('How many reports to list, at most.'),
    }),
    run: async ({ limit }) => {
      const reports = await deps.chat.reports({ limit });
      return {
        version: 1,
        reports: reports.map(({ at, squad, message, writer, text, reporter }) => ({
          at: at.toISOString(),
          squadId: squad,
          ...(message === undefined ? {} : { messageId: message }),
          ...(writer === undefined ? {} : { writerId: writer }),
          text,
          reporterId: reporter,
        })),
      };
    },
  });
}
