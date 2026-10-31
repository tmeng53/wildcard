import type { Kysely } from 'kysely';

import { MemberId, SquadId } from '../domain/awards.js';
import {
  StoredStory,
  StoredStoryMember,
  StoredStoryPost,
  type StoryMember,
  type WeekStory,
} from '../domain/week-story.js';
import type { WeekStoryStore } from '../ports.js';
import type { WeeklyAwardTables } from './postgres-awards-store.js';

/**
 * The frozen 战报 on Postgres (`supabase/migrations`): a row for the squad's part, one per
 * member, which a deleted account takes with it, and one per post on its pages, which deleting
 * the post takes with it. The database refuses to change any of them.
 */
export function createPostgresWeekStoryStore(db: Kysely<WeeklyAwardTables>): WeekStoryStore {
  return {
    async find(squad, weekStart) {
      const row = await db
        .selectFrom('week_stories')
        .select('story')
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .executeTakeFirst();
      if (row === undefined) return undefined;
      const story = StoredStory.parse(row.story);
      const [members, posts] = await Promise.all([
        db
          .selectFrom('week_story_members')
          .select(['member_id', 'page'])
          .where('squad_id', '=', squad)
          .where('week_start', '=', weekStart)
          .orderBy('position')
          .execute(),
        db
          .selectFrom('week_story_posts')
          .select(['member_id', 'post'])
          .where('squad_id', '=', squad)
          .where('week_start', '=', weekStart)
          .execute(),
      ]);
      return {
        squad: SquadId.parse(squad),
        weekStart,
        story,
        members: members.map(({ member_id, page }): StoryMember => {
          const theirs = posts
            .filter((post) => post.member_id === member_id)
            .map(({ post }) => StoredStoryPost.parse(post));
          const hottest = theirs.find((post) => post.hottest !== undefined)?.hottest;
          const best = theirs.find((post) => post.bestDisclaimer !== undefined)?.bestDisclaimer;
          return {
            member: MemberId.parse(member_id),
            ...StoredStoryMember.parse(page),
            ...(hottest === undefined ? {} : { hottest }),
            ...(best === undefined ? {} : { bestDisclaimer: best }),
          };
        }),
      };
    },

    freeze: ({ squad, weekStart, story, members }: WeekStory) =>
      db.transaction().execute(async (trx) => {
        const written = await trx
          .insertInto('week_stories')
          .values({ squad_id: squad, week_start: weekStart, story: JSON.stringify(story) })
          .onConflict((conflict) => conflict.columns(['squad_id', 'week_start']).doNothing())
          .returning('squad_id')
          .executeTakeFirst();
        // Another run froze it first: theirs stands.
        if (written === undefined || members.length === 0) return;
        // A member whose account, or a post that was deleted since the week was read fails its
        // foreign key, and the whole freeze with it: the next try reads the squad again.
        await trx
          .insertInto('week_story_members')
          .values(
            members.map((part, position) => ({
              squad_id: squad,
              week_start: weekStart,
              member_id: part.member,
              position,
              page: JSON.stringify(pageOf(part)),
            })),
          )
          .execute();
        const posts = members.flatMap(({ member, hottest, bestDisclaimer }) => [
          ...(hottest === undefined
            ? []
            : [
                {
                  member,
                  role: 'hottest',
                  checkIn: hottest.checkIn,
                  post: { version: 1, hottest },
                },
              ]),
          ...(bestDisclaimer === undefined
            ? []
            : [
                {
                  member,
                  role: 'bestDisclaimer',
                  checkIn: bestDisclaimer.checkIn,
                  post: { version: 1, bestDisclaimer },
                },
              ]),
        ]);
        if (posts.length === 0) return;
        await trx
          .insertInto('week_story_posts')
          .values(
            posts.map(({ member, role, checkIn, post }) => ({
              squad_id: squad,
              week_start: weekStart,
              member_id: member,
              role,
              check_in_id: checkIn,
              post: JSON.stringify(post),
            })),
          )
          .execute();
      }),
  };
}

/** A member's part as stored, without their posts, which are rows of their own. */
function pageOf(part: StoryMember): StoredStoryMember {
  return {
    version: part.version,
    character: part.character,
    checkedIn: part.checkedIn,
    plannedDays: part.plannedDays,
    trainedDays: part.trainedDays,
    days: part.days,
    healthyMeals: part.healthyMeals,
    cheatMeals: part.cheatMeals,
    reactionsReceived: part.reactionsReceived,
  };
}
