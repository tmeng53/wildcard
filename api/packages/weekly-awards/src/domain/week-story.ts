import { z } from 'zod';

import { TopCheckIn, type MemberId, type SquadId } from './awards.js';
import type { WeekStart } from './schedule.js';

// A squad's weekly 战报 as it stood at the week's awards (Sunday 8pm), frozen (Tracy,
// 2026-10-30): who was in the squad, that week's scene and every page without AI. Written once
// and read as it is, so nothing that happens later changes it. The AI's titles arrive later with
// the awards. The squad's part holds no one's words; each member's part holds their own, so a
// deleted account takes its words and photos with it, and each post on a page is a row of its
// own, so a deleted post does too.

/** What a day of a member's week was: a 练了 wins over a 请假条, which wins over a rest day. */
const StoryDay = z.strictObject({
  day: z.iso.date(),
  kind: z.enum(['trained', 'rest', 'disclaimer', 'none']),
  /** For a trained day: its first 练了's listed sport; missing for a sport of the member's own. */
  sport: z.string().optional(),
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
    /** 领奖台: the crown winner in the middle, up to 2 others who finished their plan beside. */
    podium: z.strictObject({ champion: z.uuid(), sides: z.array(z.uuid()) }).optional(),
    /** 吃了: the squad's meals; who ate more of what is each member's own. */
    meals: z.strictObject({ healthy: Count, cheat: Count }).optional(),
    /** 这一周: the squad's days trained against its plans; only when someone trained. */
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
  }),
]);
export type StoredStoryMember = z.infer<typeof StoredStoryMember>;

const BestDisclaimer = z.strictObject({
  checkIn: z.uuid(),
  text: z.string(),
  reactions: z.int().min(1),
});

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
  }),
]);
export type StoredStoryPost = z.infer<typeof StoredStoryPost>;

/** One member's part of a frozen 战报, with their posts on its pages that are still posted. */
export type StoryMember = { readonly member: MemberId } & StoredStoryMember & {
    /** Their check-in with the most reactions, the latest on a tie; missing when none had any. */
    readonly hottest?: TopCheckIn;
    /** The squad's best 请假条, when it was theirs. */
    readonly bestDisclaimer?: z.infer<typeof BestDisclaimer>;
  };

/** A squad's frozen 战报 for a week. */
export interface WeekStory {
  readonly squad: SquadId;
  readonly weekStart: WeekStart;
  readonly story: StoredStory;
  /** Everyone in the squad at the awards, in the order they joined, less accounts deleted since. */
  readonly members: readonly StoryMember[];
}
