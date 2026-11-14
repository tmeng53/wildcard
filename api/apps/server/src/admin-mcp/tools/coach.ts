import {
  CoachEdit,
  CoachFilePath,
  CoachSettingsChange,
  CoachId,
  MemberId,
  SquadId,
  type CoachCatalogAdmin,
  type CoachHiring,
  type CoachMemoryAdmin,
  type CoachReport,
  type CoachSettingsAdmin,
} from '@wildcard/coach';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The AI coach: the settings every coach runs with, the coaches themselves (identity and
// soul), each squad's hired coach, and what a squad's coach has done. A change applies to the next wake, with no deploy, and each one is logged with the
// whole new value, so an edit is undone by saving the old value.

interface CoachToolDependencies {
  readonly settings: CoachSettingsAdmin;
  readonly coaches: CoachCatalogAdmin;
  readonly hiring: CoachHiring;
  readonly report: CoachReport;
  readonly memory: CoachMemoryAdmin;
  readonly clock: () => Date;
}

/** `get_coach_settings`: what every coach runs with now. */
export function getCoachSettings({ settings }: CoachToolDependencies) {
  return adminTool({
    name: 'get_coach_settings',
    title: 'Read the coach settings',
    description:
      'Shows what every AI coach runs with now: whether coaching is on (for every squad that ' +
      'hired a coach), the model (openai/…), the rules every coach follows (Chinese; each ' +
      'coach’s soul comes after them), how hard it thinks, how each kind of wake goes, the hour ' +
      'morning notes arrive, the rules a reply to a post or a comment follows (replyRules, after ' +
      'the coach’s soul and nothing else), the rules the morning’s 战术板 line and notes follow ' +
      '(noteRules, the same way), the model and rules that set each member’s day ' +
      'challenge before the notes, and the holiday calendar. What its calls cost and may spend a day ' +
      'is get_ai_usage_settings’.',
    changes: false,
    input: z.strictObject({}),
    run: async () => settings.current(),
  });
}

/** `change_coach_settings`: changes some of them. */
export function changeCoachSettings({ settings }: CoachToolDependencies) {
  return adminTool({
    name: 'change_coach_settings',
    title: 'Change the coach settings',
    description:
      'Changes any of the coach settings; the rest stay as they are. Applies to the next wake. ' +
      'Coaching on, every squad that hired a coach (hire_coach) has one; off, no coach wakes. ' +
      'Before the model changes, give it a price with change_ai_usage_settings: without one ' +
      'the coach is off duty. Returns the settings now.',
    changes: true,
    input: CoachSettingsChange.refine((input) => Object.keys(input).length > 0, {
      message: 'Name at least one setting to change',
    }),
    run: async (change, { admin }) => settings.change(change, MemberId.parse(admin)),
  });
}

/** `list_coaches`: every coach, retired ones too. */
export function listCoaches({ coaches }: CoachToolDependencies) {
  return adminTool({
    name: 'list_coaches',
    title: 'List the coaches',
    description:
      'Lists every AI coach, retired ones (offered false) too, in 教练招聘会’s order: id, ' +
      'position (its place in 教练招聘会, from 1), tier (entry 入门, advanced ' +
      '进阶, pro 专业), name, title (头衔), catchphrase, the fictional 简历 the app shows ' +
      '(background 履历, yearsCoaching and experience for 执教, tags, pay 期望待遇), style, soul ' +
      '(the persona prompt only the model reads), look (the character’s art id) and offered.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({ version: 1, coaches: await coaches.list() }),
  });
}

/** `put_coach`: adds a coach, or replaces one whole. */
export function putCoach({ coaches }: CoachToolDependencies) {
  return adminTool({
    name: 'put_coach',
    title: 'Add or change a coach',
    description:
      'Adds an AI coach, or replaces every field of one (read it with list_coaches first: a ' +
      'field left out is refused, not kept). Every squad gets the same coach: its identity and ' +
      'soul never change per squad. position orders 教练招聘会 (from 1; coaches sharing one go by ' +
      'id). To retire a coach set offered to false. Ids never change ' +
      'and coaches are never deleted. Applies to the next wake. Returns the coach now.',
    changes: true,
    input: CoachEdit,
    run: async (edit, { admin }) => coaches.put(edit, MemberId.parse(admin)),
  });
}

/** `hire_coach`: hires a coach for a squad, as its captain will in the app. */
export function hireCoach({ hiring }: CoachToolDependencies) {
  return adminTool({
    name: 'hire_coach',
    title: 'Hire a coach for a squad',
    description:
      'Hires an offered AI coach (list_coaches) for a squad that has none, logged as yours; ' +
      'its first wake comes on the next coach run while coaching is on. A squad has one coach ' +
      'at a time: fire_coach first to change it. The squad’s memory stays with the squad, so ' +
      'a new coach reads what the last one wrote.',
    changes: true,
    input: z.strictObject({
      squad: SquadId.describe('The squad’s id.'),
      coach: CoachId.describe('The coach’s id, such as xiaohun.'),
    }),
    run: async ({ squad, coach }, { admin }) => ({
      version: 1,
      ...(await hiring.hire({ squad, coach, by: MemberId.parse(admin) })),
    }),
  });
}

/** `fire_coach`: fires a squad's coach. */
export function fireCoach({ hiring }: CoachToolDependencies) {
  return adminTool({
    name: 'fire_coach',
    title: 'Fire a squad’s coach',
    description:
      'Fires a squad’s AI coach, logged as yours: it wakes for the squad no more. Its memory ' +
      'files, 战术板 lines and usage stay with the squad.',
    changes: true,
    input: z.strictObject({ squad: SquadId.describe('The squad’s id.') }),
    run: async ({ squad }, { admin }) => ({
      version: 1,
      ...(await hiring.fire({ squad, by: MemberId.parse(admin) })),
    }),
  });
}

/** `get_squad_coaching`: what one squad's coach has done, and what it cost. */
export function getSquadCoaching({ report, clock }: CoachToolDependencies) {
  return adminTool({
    name: 'get_squad_coaching',
    title: 'Read a squad’s coaching',
    description:
      'Shows a squad’s AI coach (null when it hired none) and what it has done: its memory files now (squad.md, memory.md and a ' +
      'page per member, stored as people/<member id>.md; the model sees each member as 队员N; ' +
      'and each coach’s own page, coaches/<coach id>.md, which only that coach reads, as me.md), ' +
      'its last 14 战术板 lines, its last 20 wakes (checkIn, comment or daily, state, tries, why ' +
      'the last try failed, and each tool call of its runs in order: the tool, its arguments and ' +
      'what it answered, a read by its length only) and the tokens and cost (millionths of a US dollar) of its runs (wakes, ' +
      'letters, previews) so far and of the last 7 days. Members’ own words are in the files: read, don’t share.',
    changes: false,
    input: z.strictObject({ squad: SquadId.describe('The squad’s id.') }),
    run: async ({ squad }) => report.squad(squad, clock()),
  });
}

/** `edit_coach_files`: rewrites one of a squad's coach memory files. */
export function editCoachFiles({ memory }: CoachToolDependencies) {
  return adminTool({
    name: 'edit_coach_files',
    title: 'Rewrite a squad’s coach memory file',
    description:
      'Replaces one of a squad’s coach memory files with a new body, logged as yours; an empty ' +
      'body clears it. Paths and bodies are as get_squad_coaching shows them: squad.md, ' +
      'memory.md, people/<member id>.md or coaches/<coach id>.md, members named as ' +
      '{队员:<member id>}. Every version ' +
      'is kept. The coach reads the new body on its next wake. Returns the squad’s files now.',
    changes: true,
    input: z.strictObject({
      squad: SquadId.describe('The squad’s id.'),
      path: CoachFilePath.describe(
        'squad.md, memory.md, people/<member id>.md or coaches/<coach id>.md',
      ),
      body: z.string().max(20_000).describe('The file’s whole new text, Chinese.'),
    }),
    run: async (input) => memory.rewrite(input),
  });
}

export const coachTools = (deps: CoachToolDependencies) => [
  getCoachSettings(deps),
  changeCoachSettings(deps),
  listCoaches(deps),
  putCoach(deps),
  hireCoach(deps),
  fireCoach(deps),
  getSquadCoaching(deps),
  editCoachFiles(deps),
];
