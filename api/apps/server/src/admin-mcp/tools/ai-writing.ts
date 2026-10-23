import {
  DraftSettingsChange,
  MemberId as DraftMember,
  ModelName as DraftModel,
  type DraftSettingsAdmin,
} from '@wildcard/disclaimer-drafts';
import {
  AwardSettingsChange,
  MemberId as AwardsMember,
  ModelName as AwardsModel,
  type AwardSettingsAdmin,
} from '@wildcard/weekly-awards';
import { z } from 'zod';

import { ModelChoice } from '../../model-choice.js';
import { adminTool } from '../admin-tool.js';

// What the AI writes with: the model, its standing instructions and its dials, for 请假条
// drafts and for the weekly awards. A change applies to the next request, with no deploy, and
// each one is logged with the whole new value, so an edit is undone by saving the old value.

interface AiWritingToolDependencies {
  readonly drafts: DraftSettingsAdmin;
  readonly awards: AwardSettingsAdmin;
}

/** A change names at least one setting. */
const someChange = <Change extends z.ZodObject>(change: Change) =>
  change.refine((input) => Object.keys(input).length > 0, {
    message: 'Name at least one setting to change',
  });

/** `get_disclaimer_draft_settings`: what 请假条 drafts are written with now. */
export function getDisclaimerDraftSettings({ drafts }: AiWritingToolDependencies) {
  return adminTool({
    name: 'get_disclaimer_draft_settings',
    title: 'Read the 请假条 draft settings',
    description:
      'Shows what AI 请假条 drafts are written with now: whether they are on, the model ' +
      '(provider/model), its standing instructions, the batches a member may ask for in 24 ' +
      'hours, and how often a request gets one of the week’s memes.',
    changes: false,
    input: z.strictObject({}),
    run: async () => drafts.current(),
  });
}

/** `change_disclaimer_draft_settings`: changes some of them. */
export function changeDisclaimerDraftSettings({ drafts }: AiWritingToolDependencies) {
  return adminTool({
    name: 'change_disclaimer_draft_settings',
    title: 'Change the 请假条 draft settings',
    description:
      'Changes any of the 请假条 draft settings; the rest stay as they are. Applies to the next ' +
      'request. Turning drafts off makes the app show its dice. A model whose provider has no ' +
      'API key on the server writes nothing, as if drafts were off. Returns the settings now.',
    changes: true,
    input: someChange(
      DraftSettingsChange.extend({ model: ModelChoice.pipe(DraftModel).optional() }),
    ),
    run: async (change, { admin }) => drafts.change(change, DraftMember.parse(admin)),
  });
}

/** `get_weekly_award_settings`: what the weekly awards are written with now. */
export function getWeeklyAwardSettings({ awards }: AiWritingToolDependencies) {
  return adminTool({
    name: 'get_weekly_award_settings',
    title: 'Read the weekly award settings',
    description:
      'Shows what each squad’s weekly awards (本周颁奖) are written with now: the model ' +
      '(provider/model), its standing instructions, and what each move looks like for the ' +
      'model choosing one per award.',
    changes: false,
    input: z.strictObject({}),
    run: async () => awards.current(),
  });
}

/** `change_weekly_award_settings`: changes some of them. */
export function changeWeeklyAwardSettings({ awards }: AiWritingToolDependencies) {
  return adminTool({
    name: 'change_weekly_award_settings',
    title: 'Change the weekly award settings',
    description:
      'Changes any of the weekly award settings; the rest stay as they are. `moves` changes ' +
      'only the moves it names; the moves themselves are the app’s character clips, so no move ' +
      'can be added here. Applies to the next try at a squad’s awards. A model whose provider ' +
      'has no API key on the server writes nothing, and the awards stay pending. Returns the ' +
      'settings now.',
    changes: true,
    input: someChange(
      AwardSettingsChange.extend({ model: ModelChoice.pipe(AwardsModel).optional() }),
    ),
    run: async (change, { admin }) => awards.change(change, AwardsMember.parse(admin)),
  });
}

export const aiWritingTools = (deps: AiWritingToolDependencies) => [
  getDisclaimerDraftSettings(deps),
  changeDisclaimerDraftSettings(deps),
  getWeeklyAwardSettings(deps),
  changeWeeklyAwardSettings(deps),
];
