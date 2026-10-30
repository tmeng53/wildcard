import type { Kysely } from 'kysely';

import { MemberId, SquadId } from '../domain/awards.js';
import { StoredStory, StoredStoryMember, type WeekStory } from '../domain/week-story.js';
import type { WeekStoryStore } from '../ports.js';
import type { WeeklyAwardTables } from './postgres-awards-store.js';

/**
 * The frozen 战报 on Postgres (`supabase/migrations`): a row for the squad's part and one per
 * member, which a deleted account takes with it. The database refuses to change either.
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
      const members = await db
        .selectFrom('week_story_members')
        .select(['member_id', 'page'])
        .where('squad_id', '=', squad)
        .where('week_start', '=', weekStart)
        .orderBy('position')
        .execute();
      return {
        squad: SquadId.parse(squad),
        weekStart,
        story,
        members: members.map(({ member_id, page }) => ({
          member: MemberId.parse(member_id),
          ...StoredStoryMember.parse(page),
        })),
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
        // A member whose account was deleted since the week was read fails the foreign key,
        // and the whole freeze with it: the next try reads the squad again.
        await trx
          .insertInto('week_story_members')
          .values(
            members.map(({ member, ...page }, position) => {
              return {
                squad_id: squad,
                week_start: weekStart,
                member_id: member,
                position,
                page: JSON.stringify(page),
              };
            }),
          )
          .execute();
      }),
  };
}
