import {
  CampaignId,
  CampaignStatus,
  SWITCH_MODE_OF,
  type Campaign,
  type Campaigns,
} from '@wildcard/campaigns';
import type { Art } from '@wildcard/art';
import { SceneEdit, type Scenes, type ScenesAdmin } from '@wildcard/scenes';
import {
  DayOffset,
  MonthDay,
  SwitchId,
  type Switch,
  type Switches,
  type SwitchesAdmin,
} from '@wildcard/switches';
import { UnlockRuleEdit, type Unlocks, type UnlocksAdmin } from '@wildcard/unlocks';
import { z } from 'zod';

import { newYorkDay } from '../../new-york-day.js';
import { adminTool } from '../admin-tool.js';

// Campaigns (Tracy, 2026-11-04): a holiday, an anniversary or a race day is a bundle of generic
// pieces an admin puts together, never a concept in code: global switches with their days, the
// scenes that follow them (a takeover scene every home shows while its switch is on), and the
// unlock rules of a limited store's pieces. A new campaign is a draft nobody sees; in preview
// only the members on the preview list see it, on the day each pretends it is
// (set_switch_preview), in the App Store build; live, everyone sees it on its days; stopped,
// nobody. Pieces members unlocked are never taken back.

interface CampaignToolDependencies {
  readonly campaigns: Campaigns;
  readonly switches: Switches & SwitchesAdmin;
  readonly scenes: Scenes & ScenesAdmin;
  readonly unlocks: Pick<Unlocks & UnlocksAdmin, 'rules' | 'putRule'>;
  readonly art: Pick<Art, 'manifest'>;
  readonly clock: () => Date;
}

const CampaignSwitch = z.strictObject({
  id: SwitchId.meta({ description: 'The switch’s id, camelCase, such as `thanksgiving`.' }),
  label: z.string().trim().min(1).max(80).meta({ description: 'What it is for, for admins.' }),
  window: z
    .strictObject({
      start: MonthDay.meta({ description: 'First day, `MM-DD`, New York time.' }),
      end: MonthDay.meta({
        description: 'Last day, `MM-DD`; may be before start (over New Year).',
      }),
    })
    .meta({
      description: 'The days it is on, both included, every year while the campaign is live.',
    }),
});

/** What one campaign bundles now: its switches, the scenes and rules that follow them. */
async function bundleOf(campaign: Campaign, deps: CampaignToolDependencies) {
  const owned = new Set(campaign.switches);
  const [switches, scenes, rules, art] = await Promise.all([
    deps.switches.list(),
    deps.scenes.list(),
    deps.unlocks.rules(),
    deps.art.manifest(),
  ]);
  const uploaded = new Set<string>(art.files.map(({ path }) => path));
  const following = <T extends { readonly switchId?: string | null }>(items: readonly T[]) =>
    items.filter(({ switchId }) => typeof switchId === 'string' && owned.has(switchId));
  const ownScenes = following(scenes);
  return {
    switches: switches.filter(({ id }) => owned.has(id)),
    scenes: ownScenes,
    unlockRules: following(rules),
    // A scene new to this campaign has no art in older builds: its pictures must be uploaded.
    missingArt: ownScenes.flatMap(({ id }) =>
      ['day', 'night']
        .map((time) => `scenes/${id}-${time}@3x.png`)
        .filter((path) => !uploaded.has(path)),
    ),
  };
}

/** A campaign with what it bundles, as the tools answer. */
async function shown(campaign: Campaign, deps: CampaignToolDependencies) {
  return {
    ...campaign,
    changedAt: campaign.changedAt.toISOString(),
    ...(await bundleOf(campaign, deps)),
  };
}

/** What moving `campaign` to `status` does, in plain words, for the admin to check first. */
async function plan(
  { campaign, status }: { readonly campaign: Campaign; readonly status: CampaignStatus },
  deps: CampaignToolDependencies,
) {
  const { switches, scenes, unlockRules, missingArt } = await bundleOf(campaign, deps);
  const who = {
    draft: 'Nobody sees it.',
    preview:
      'Only members on the preview list (set_switch_preview) see it, each on the day they pretend it is.',
    live: 'Every member sees it, on its days, every year until it is stopped.',
    stopped: 'Nobody sees it from now on; pieces members unlocked stay theirs.',
  }[status];
  const days = (each: Switch) =>
    each.window === undefined
      ? 'every day'
      : `${each.window.start} to ${each.window.end} (New York)`;
  return [
    `${campaign.label}: ${campaign.status} → ${status}. ${who}`,
    ...switches.map((each) => {
      const takeovers = scenes.filter(
        ({ switchId, takeover }) => switchId === each.id && takeover === true,
      );
      const picks = scenes.filter(
        ({ switchId, takeover }) => switchId === each.id && takeover !== true,
      );
      const pieces = unlockRules.filter(({ switchId }) => switchId === each.id);
      return [
        `Switch ${each.id} (${each.label}), ${days(each)}:`,
        ...takeovers.map(({ id }) => `  every squad’s home shows the ${id} scene`),
        ...picks.map(({ id }) => `  squads may pick the ${id} scene`),
        ...pieces.map(
          ({ kind, id, after, sports }) =>
            `  ${kind} ${id} unlocks after ${String(after)} 练了${sports.length === 0 ? '' : ` in ${sports.join(', ')}`} on these days`,
        ),
      ].join('\n');
    }),
    ...(missingArt.length === 0
      ? []
      : [
          `Warning, art not uploaded yet (put_art): ${missingArt.join(', ')}. Apps show the gym instead.`,
        ]),
  ].join('\n');
}

/** `get_campaigns`: every campaign and what it bundles. */
export function getCampaigns(deps: CampaignToolDependencies) {
  return adminTool({
    name: 'get_campaigns',
    title: 'Read the campaigns',
    description:
      'Shows every campaign (a holiday, an anniversary, any moment an admin bundles), newest ' +
      'change first: id, label, status (draft, preview, live, stopped), its switches with their ' +
      'days, the scenes and unlock rules that follow them, and any scene art not uploaded yet. ' +
      'Also lists who is on the preview list and the day each pretends it is.',
    changes: false,
    input: z.strictObject({}),
    run: async () => ({
      version: 1,
      campaigns: await Promise.all((await deps.campaigns.list()).map((each) => shown(each, deps))),
      previewers: await deps.switches.previewers(),
    }),
  });
}

/** `put_campaign`: adds a campaign as a draft, or changes what one bundles. */
export function putCampaign(deps: CampaignToolDependencies) {
  return adminTool({
    name: 'put_campaign',
    title: 'Add or change a campaign',
    description:
      'Bundles a holiday or any other moment from generic pieces, in one call: its switches ' +
      '(each with the days it is on), the scenes that follow them (a scene with takeover true ' +
      'is what every squad’s home shows while its switch is on; one without may be picked) and ' +
      'the unlock rules of a limited store’s pieces (switchId one of the campaign’s switches: ' +
      'only 练了 on its days count, and a piece stays the member’s all year). A new campaign is ' +
      'a draft nobody sees; a changed one keeps its status. Scenes and rules are put whole, as ' +
      'put_scene and put_unlock_rule do. Broadcast notices (the 「快到了」 notice, the holiday-day ' +
      'opening) go in with put_broadcast. Then try it with set_campaign_status preview and ' +
      'set_switch_preview, and publish with set_campaign_status live. Returns the campaign.',
    changes: true,
    input: z
      .strictObject({
        id: CampaignId.meta({
          description: 'Its id, camelCase, such as `thanksgiving`. Never changes.',
        }),
        label: z.string().trim().min(1).max(80).meta({ description: 'What it is, for admins.' }),
        switches: z.array(CampaignSwitch).min(1).max(10),
        scenes: z.array(SceneEdit).max(10).default([]),
        unlockRules: z.array(UnlockRuleEdit).max(40).default([]),
      })
      .refine(
        ({ switches, scenes, unlockRules }) => {
          const owned = new Set(switches.map(({ id }) => id));
          return [...scenes, ...unlockRules].every(
            ({ switchId }) => typeof switchId === 'string' && owned.has(switchId),
          );
        },
        { message: 'every scene and unlock rule follows one of the campaign’s switches' },
      ),
    run: async ({ id, label, switches, scenes, unlockRules }, { admin }) => {
      const current = await deps.campaigns.find(id);
      const mode = SWITCH_MODE_OF[current?.status ?? 'draft'];
      for (const each of switches) await deps.switches.put({ ...each, mode });
      for (const each of scenes) await deps.scenes.putScene(each);
      for (const each of unlockRules) await deps.unlocks.putRule(each);
      const campaign = await deps.campaigns.put({
        id,
        label,
        switches: [...new Set([...(current?.switches ?? []), ...switches.map((each) => each.id)])],
        by: admin,
      });
      return { version: 1, campaign: await shown(campaign, deps) };
    },
  });
}

/** `set_campaign_status`: previews, publishes or stops a campaign, after showing what it does. */
export function setCampaignStatus(deps: CampaignToolDependencies) {
  return adminTool({
    name: 'set_campaign_status',
    title: 'Preview, publish or stop a campaign',
    description:
      'Moves a campaign to draft, preview (only the preview list sees it), live (everyone, on ' +
      'its days) or stopped (nobody; unlocked pieces stay). Without confirm it changes nothing ' +
      'and answers with what the move would do, in plain words: show that to the admin and ask ' +
      'before calling again with confirm true. Apps see a change within a minute.',
    changes: true,
    input: z.strictObject({
      id: CampaignId,
      status: CampaignStatus,
      confirm: z.boolean().default(false).meta({
        description: 'True only after the admin read the plan this tool answered without it.',
      }),
    }),
    run: async ({ id, status, confirm }, { admin }) => {
      const current = await deps.campaigns.find(id);
      if (current === undefined) return { version: 1, error: `There is no campaign ${id}.` };
      const what = await plan({ campaign: current, status }, deps);
      if (!confirm) return { version: 1, changed: false, plan: what };
      const mode = SWITCH_MODE_OF[status];
      for (const each of (await deps.switches.list()).filter(({ id: owned }) =>
        current.switches.includes(owned),
      ))
        await deps.switches.put({
          id: each.id,
          label: each.label,
          mode,
          ...(each.window === undefined ? {} : { window: each.window }),
        });
      const moved = await deps.campaigns.move({ id, status, by: admin });
      return { version: 1, changed: true, plan: what, campaign: await shown(moved, deps) };
    },
  });
}

/** `set_switch_preview`: puts a member on the preview list, with the day they pretend it is. */
export function setSwitchPreview(deps: CampaignToolDependencies) {
  return adminTool({
    name: 'set_switch_preview',
    title: 'Preview campaigns on a phone',
    description:
      'Puts a member (the calling admin when left out) on the preview list or takes them off. ' +
      'A member on it sees campaigns in preview in the App Store app, with their own account, ' +
      'as on `day` (YYYY-MM-DD): limited stores, takeover scenes and notices act as on that day. ' +
      'Only switches see the pretend day; their check-ins, weeks and 战报 keep the real date. ' +
      'Leave day out for today. Take them off (preview false) when done. Returns the preview list.',
    changes: true,
    input: z.strictObject({
      member: z.uuid().optional().meta({ description: 'The member’s id; leave out for yourself.' }),
      preview: z.boolean(),
      day: z.iso.date().optional().meta({ description: 'The day to pretend it is, New York.' }),
    }),
    run: async ({ member, preview, day }, { admin }) => {
      const today = newYorkDay(deps.clock());
      const offset =
        !preview || day === undefined
          ? 0
          : Math.round((Date.parse(day) - Date.parse(today)) / 86_400_000);
      const previewers = await deps.switches.setView({
        member: member ?? admin,
        view: { previewer: preview, dayOffset: DayOffset.parse(offset) },
        by: admin,
      });
      return {
        version: 1,
        previewers: previewers.map((each) => ({
          ...each,
          day: new Date(Date.parse(today) + each.dayOffset * 86_400_000).toISOString().slice(0, 10),
        })),
      };
    },
  });
}

export const campaignTools = (deps: CampaignToolDependencies) => [
  getCampaigns(deps),
  putCampaign(deps),
  setCampaignStatus(deps),
  setSwitchPreview(deps),
];
