import {
  CampaignId,
  CampaignStatus,
  CampaignSwitchTakenError,
  SWITCH_MODE_OF,
  type Campaign,
  type Campaigns,
} from '@wildcard/campaigns';
import type { Art } from '@wildcard/art';
import { SceneEdit, type Scenes, type ScenesAdmin } from '@wildcard/scenes';
import {
  CoachNote,
  DayOffset,
  MonthDay,
  SwitchId,
  type Switch,
  type Switches,
  type SwitchesAdmin,
} from '@wildcard/switches';
import {
  PieceEdit,
  StoreEdit,
  UnlockRuleEdit,
  type Unlocks,
  type UnlocksAdmin,
} from '@wildcard/unlocks';
import { z } from 'zod';

import { newYorkDay } from '../../new-york-day.js';
import { adminTool } from '../admin-tool.js';

// Campaigns (Tracy, 2026-11-04): a holiday, an anniversary or a race day is a bundle of generic
// pieces an admin puts together, never a concept in code: global switches with their days, the
// scenes that follow them (a takeover scene every home shows while its switch is on), and the
// limited stores and pieces on them with the rules that open them. A new campaign is a draft nobody sees; in preview
// only the members on the preview list see it, on the day each pretends it is
// (set_switch_preview), in the App Store build; live, everyone sees it on its days; stopped,
// nobody. Pieces members unlocked are never taken back.

interface CampaignToolDependencies {
  readonly campaigns: Campaigns;
  readonly switches: Switches & SwitchesAdmin;
  readonly scenes: Scenes & ScenesAdmin;
  readonly unlocks: Pick<
    Unlocks & UnlocksAdmin,
    'rules' | 'putRule' | 'stores' | 'putStore' | 'pieces' | 'putPiece'
  >;
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
  coachNote: CoachNote.optional(),
});

/** What one campaign bundles now: its switches and the scenes, stores, pieces and rules on them. */
async function bundleOf(campaign: Campaign, deps: CampaignToolDependencies) {
  const owned = new Set(campaign.switches);
  const [switches, scenes, stores, pieces, rules, art] = await Promise.all([
    deps.switches.list(),
    deps.scenes.list(),
    deps.unlocks.stores(),
    deps.unlocks.pieces(),
    deps.unlocks.rules(),
    deps.art.manifest(),
  ]);
  const uploaded = new Set<string>(art.files.map(({ path }) => path));
  const following = <T extends { readonly switchId?: string | null }>(items: readonly T[]) =>
    items.filter(({ switchId }) => typeof switchId === 'string' && owned.has(switchId));
  const ownScenes = following(scenes);
  const ownStores = following(stores);
  const storeIds = new Set(ownStores.map(({ id }) => id));
  const ownPieces = pieces.filter(
    (piece) => storeIds.has(piece.storeId) || following([piece]).length > 0,
  );
  const ids = new Set([
    ...ownStores.map(({ id }) => `store:${id}`),
    ...ownPieces.map(({ id }) => `piece:${id}`),
  ]);
  return {
    switches: switches.filter(({ id }) => owned.has(id)),
    scenes: ownScenes,
    stores: ownStores,
    pieces: ownPieces,
    unlockRules: rules.filter(({ kind, id }) => ids.has(`${kind}:${id}`)),
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
  const { switches, scenes, stores, pieces, unlockRules, missingArt } = await bundleOf(
    campaign,
    deps,
  );
  const ruleOf = (id: string) =>
    unlockRules.find((rule) => rule.kind === 'piece' && rule.id === id);
  const opens = ({ id, starter }: { readonly id: string; readonly starter: boolean }) => {
    if (starter) return 'is out for everyone';
    const rule = ruleOf(id);
    if (rule === undefined) return 'opens only as a gift (a broadcast’s gifts)';
    const sports = rule.sports.length === 0 ? '' : ` in ${rule.sports.join(', ')}`;
    return `unlocks after ${String(rule.after)} 练了${sports} on these days`;
  };
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
      const open = stores.filter(({ switchId }) => switchId === each.id);
      return [
        `Switch ${each.id} (${each.label}), ${days(each)}:`,
        ...takeovers.map(({ id }) => `  every squad’s home shows the ${id} scene`),
        ...picks.map(({ id }) => `  squads may pick the ${id} scene`),
        ...open.flatMap(({ id }) => [
          `  store ${id} opens on the 商店街`,
          ...pieces
            .filter(({ storeId, switchId }) => storeId === id && switchId === undefined)
            .map((piece) => `    piece ${piece.id} ${opens(piece)}`),
        ]),
        ...pieces
          .filter(({ switchId }) => switchId === each.id)
          .map((piece) => `  piece ${piece.id} (store ${piece.storeId}) ${opens(piece)}`),
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
      'days, the scenes, stores and pieces on them with the rules that open the pieces, and any ' +
      'scene art not uploaded yet. ' +
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
      '(new ids, or ones it already owns; never winter or another campaign’s, each with the days it is on), the scenes that follow them (a scene with takeover true ' +
      'is what every squad’s home shows while its switch is on; one without may be picked), the ' +
      'limited stores and pieces on them (a store or piece whose switchId is one of the ' +
      'campaign’s switches, or a piece in such a store) and the unlock rules of those pieces: ' +
      'only 练了 on its days count, and a piece stays the member’s all year. A piece without a ' +
      'rule opens only as a broadcast’s gift; a starter is out for everyone. A new campaign is a draft no member can open (its names and colours are in the public catalog, as every limited scene’s and store’s are); a changed ' +
      'one keeps its status. Each is put whole, as put_scene, put_store, put_piece and ' +
      'put_unlock_rule do; art goes up first with put_art. Broadcast notices (the 「快到了」 notice, the holiday-day ' +
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
        stores: z.array(StoreEdit).max(10).default([]),
        pieces: z.array(PieceEdit).max(60).default([]),
        unlockRules: z.array(UnlockRuleEdit).max(60).default([]),
      })
      .refine(
        ({ switches, scenes, stores, pieces, unlockRules }) => {
          const owned = new Set(switches.map(({ id }) => id));
          const follows = ({ switchId }: { readonly switchId?: string | null }) =>
            typeof switchId === 'string' && owned.has(switchId);
          const ownStores = new Set(stores.map(({ id }) => id));
          const ownPieces = new Set(pieces.map(({ id }) => id));
          return (
            scenes.every(follows) &&
            stores.every(follows) &&
            pieces.every((piece) => follows(piece) || ownStores.has(piece.storeId)) &&
            unlockRules.every(({ kind, id }) =>
              kind === 'piece' ? ownPieces.has(id) : kind === 'store' && ownStores.has(id),
            )
          );
        },
        {
          message:
            'every scene and store follows one of the campaign’s switches, every piece does or ' +
            'hangs in one of its stores, and every rule opens one of its stores or pieces',
        },
      ),
    run: async ({ id, label, switches, scenes, stores, pieces, unlockRules }, { admin }) => {
      const current = await deps.campaigns.find(id);
      const mode = SWITCH_MODE_OF[current?.status ?? 'draft'];
      // A campaign makes its switches: one already there that isn't its own (winter, or another
      // campaign's) would be set to this campaign's mode for everyone.
      const existing = new Set((await deps.switches.list()).map((each) => each.id));
      const taken = switches.find(
        (each) => existing.has(each.id) && !(current?.switches ?? []).includes(each.id),
      );
      if (taken !== undefined) throw new CampaignSwitchTakenError(id, taken.id);
      for (const each of switches) await deps.switches.put({ ...each, mode });
      for (const each of scenes) await deps.scenes.putScene(each);
      for (const each of stores) await deps.unlocks.putStore(each);
      for (const each of pieces) await deps.unlocks.putPiece(each);
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
          ...(each.coachNote === undefined ? {} : { coachNote: each.coachNote }),
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
