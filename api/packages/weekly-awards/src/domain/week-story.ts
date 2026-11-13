import { z } from 'zod';

import { Place, PlaceKey } from '@wildcard/place-ids';

import { TopCheckIn, type MemberId, type SquadId } from './awards.js';
import type { WeekStart } from './schedule.js';

// A squad's weekly 战报 as it stood at the week's awards (Sunday 8pm), frozen (Tracy,
// 2026-10-30): who was in the squad, that week's scene and every page without AI. Written once
// and read as it is, so nothing that happens later changes it. The AI's titles arrive later with
// the awards. The squad's part holds no one's words; each member's part holds their own, so a
// deleted account takes its words and photos with it, and each post on a page is a row of its
// own, so a deleted post does too.

/** What a day of a member's week was: a 训练 wins over a 请假条, which wins over a rest day. */
const StoryDay = z.strictObject({
  day: z.iso.date(),
  kind: z.enum(['trained', 'rest', 'disclaimer', 'none']),
  /** For a trained day: its first 训练's listed sport; missing for a sport of the member's own. */
  sport: z.string().optional(),
  /** For a trained day: the minutes its 训练 logged; missing when none did, or frozen before. */
  minutes: z.int().min(1).optional(),
});
export type StoryDay = z.infer<typeof StoryDay>;

const Count = z.int().min(0);

/** Stored JSON (`week_stories.story`): the squad's part. */
export const StoredStory = z.discriminatedUnion('version', [
  z.strictObject({
    version: z.literal(1),
    /** The squad's name that week. */
    name: z.string().min(1),
    /** The scene the squad trained on that week, as the squads module names it. */
    scene: z.string().min(1),
    /**
     * Only in the first stories frozen, never read: the podium is read from the members' frozen
     * days, so the first weeks stand on it too.
     */
    podium: z.unknown().optional(),
    /** 吃了: the squad's meals; who ate more of what is each member's own. */
    meals: z.strictObject({ healthy: Count, cheat: Count }).optional(),
    /**
     * 这一周: the 训练 the squad's members sent to it that week (several on one day each
     * counting; days trained in stories frozen before 2026-11-09, counted again by a migration)
     * and its members' plans added up, as it froze; only when someone trained. The 战报 shows
     * the 训练 against the squad's weekly goal instead of the plans.
     */
    ending: z.strictObject({ done: Count, plan: Count }).optional(),
  }),
]);
export type StoredStory = z.infer<typeof StoredStory>;

/** Stored JSON (`week_story_members.page`): one member's part. */
export const StoredStoryMember = z.discriminatedUnion('version', [
  z.strictObject({
    version: z.literal(1),
    /**
     * Their character that week (nickname and look) as the members module shapes it, or null
     * when they hadn't made one. The API parses it with the members module's schema.
     */
    character: z.record(z.string(), z.unknown()).nullable(),
    /** Whether they checked in anything that week before the awards. */
    checkedIn: z.boolean(),
    plannedDays: Count,
    trainedDays: Count,
    /** Monday first. */
    days: z.array(StoryDay).length(7),
    healthyMeals: Count,
    cheatMeals: Count,
    reactionsReceived: Count,
    /**
     * When they reached their days trained, if they trained: breaks a tie on the podium in
     * favour of whoever got there first. Missing in stories frozen before it (the join order
     * breaks their ties).
     */
    reachedAt: z.iso.datetime().optional(),
    /** Stories frozen before `reachedAt` kept when the member finished their plan; never read. */
    planFinishedAt: z.iso.datetime().optional(),
  }),
]);
export type StoredStoryMember = z.infer<typeof StoredStoryMember>;

const BestDisclaimer = z.strictObject({
  checkIn: z.uuid(),
  text: z.string(),
  reactions: z.int().min(1),
});

/** A rated meal of theirs on 小队菜单, and its place on it (0 first). */
const MenuDish = z.strictObject({
  checkIn: z.uuid(),
  day: z.iso.date(),
  rank: z.int().min(0),
  rating: z.strictObject({ healthy: z.int().min(1).max(5), tasty: z.int().min(1).max(5) }),
  caption: z.string().optional(),
  /** Its first photo's path. */
  photo: z.string().optional(),
  place: Place.optional(),
});
export type MenuDish = z.infer<typeof MenuDish>;

/**
 * A 训练 of theirs tagged with a place, for 小队最爱去 and 新发现: the place as that post tagged
 * it, the place's position among the week's places (0 the most trained at), and whether nobody
 * had posted a 训练 there to the squad before the week.
 */
const PlaceVisit = z.strictObject({
  checkIn: z.uuid(),
  day: z.iso.date(),
  /** When it was posted: of the visits left, the latest posted gives the place's tag. */
  postedAt: z.iso.datetime(),
  key: PlaceKey,
  place: Place,
  rank: z.int().min(0),
  firstTime: z.boolean(),
});
export type PlaceVisit = z.infer<typeof PlaceVisit>;

/**
 * Stored JSON (`week_story_posts.post`): one of the member's posts on the 战报's pages, kept
 * apart from their part so that deleting the post takes its words and photos with it.
 */
export const StoredStoryPost = z.discriminatedUnion('version', [
  z.strictObject({
    version: z.literal(1),
    /** Their check-in with the most reactions, the latest on a tie. */
    hottest: TopCheckIn.optional(),
    /** The squad's best 请假条, theirs. */
    bestDisclaimer: BestDisclaimer.optional(),
    /** A meal of theirs on 小队菜单. */
    menuDish: MenuDish.optional(),
    /** A 训练 of theirs at one of the week's places. */
    placeVisit: PlaceVisit.optional(),
  }),
]);
export type StoredStoryPost = z.infer<typeof StoredStoryPost>;

/** One member's part of a frozen 战报, with their posts on its pages that are still posted. */
export type StoryMember = { readonly member: MemberId } & StoredStoryMember & {
    /** Their check-in with the most reactions, the latest on a tie; missing when none had any. */
    readonly hottest?: TopCheckIn;
    /** The squad's best 请假条, when it was theirs. */
    readonly bestDisclaimer?: z.infer<typeof BestDisclaimer>;
    /** Their meals on 小队菜单, still posted. */
    readonly menu?: readonly MenuDish[];
    /** Their 训练 at the week's places, still posted. */
    readonly placeVisits?: readonly PlaceVisit[];
  };

/** A squad's frozen 战报 for a week. */
export interface WeekStory {
  readonly squad: SquadId;
  readonly weekStart: WeekStart;
  readonly story: StoredStory;
  /** Everyone in the squad at the awards, in the order they joined, less accounts deleted since. */
  readonly members: readonly StoryMember[];
}
