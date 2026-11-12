import {
  AiUsageSettingsChange,
  MemberId as AiUsageMember,
  type AiUsageSettingsAdmin,
} from '@wildcard/ai-usage';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// What every model call costs and how much a day may go on them: each model's prices and the
// daily caps per squad and for every squad together. Every call (the coach, 请假条 drafts, the
// weekly awards) is counted to its member and squad at these prices. A change applies to the next
// call, with no deploy, and each one is logged with the whole new value.

interface AiUsageToolDependencies {
  readonly settings: AiUsageSettingsAdmin;
}

/** `get_ai_usage_settings`: the prices and caps now. */
export function getAiUsageSettings({ settings }: AiUsageToolDependencies) {
  return adminTool({
    name: 'get_ai_usage_settings',
    title: 'Read the AI prices and daily caps',
    description:
      'Shows what every model call is counted at and may spend: each model’s prices (by ' +
      'provider/model, per million input, cached input and output tokens, in millionths of a US ' +
      'dollar), what one squad’s AI may spend a day on its own clock, and what every squad ' +
      'together may spend a New York day, both in millionths of a US dollar. Every call for a ' +
      'squad or its members counts: the coach, 请假条 drafts and the weekly awards.',
    changes: false,
    input: z.strictObject({}),
    run: async () => settings.current(),
  });
}

/** `change_ai_usage_settings`: changes some of them. */
export function changeAiUsageSettings({ settings }: AiUsageToolDependencies) {
  return adminTool({
    name: 'change_ai_usage_settings',
    title: 'Change the AI prices and daily caps',
    description:
      'Changes any of the AI usage settings; the rest stay as they are. `prices` replaces the ' +
      'whole list: send every model’s prices. A call to a model without a price is never made ' +
      '(the coach goes off duty, 请假条 shows the dice, the weekly awards stay pending), so price ' +
      'a model before a setting names it. Once a squad’s spending that day reaches its cap, the ' +
      'coach is off duty and 请假条 shows the dice until the next day; the weekly awards are ' +
      'counted but never held back. Applies to the next call. Returns the settings now.',
    changes: true,
    input: AiUsageSettingsChange.refine((input) => Object.keys(input).length > 0, {
      message: 'Name at least one setting to change',
    }),
    run: async (change, { admin }) => settings.change(change, AiUsageMember.parse(admin)),
  });
}

export const aiUsageTools = (deps: AiUsageToolDependencies) => [
  getAiUsageSettings(deps),
  changeAiUsageSettings(deps),
];
