import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely, type Selectable, type Transaction } from 'kysely';
import { z } from 'zod';

import { InviteCode } from '../domain/invite-code.js';
import { Scene, SceneWeek } from '../domain/scene.js';
import {
  captainOf,
  MemberId,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  SquadId,
  SquadName,
  type Squad,
} from '../domain/squad.js';
import type { CaptainOutcome, CreateOutcome, JoinOutcome, SquadStore } from '../ports.js';
import type { DB, Squads } from './tables.js';

/** The tables this store reads and writes, as generated from the migrations. */
export type SquadTables = DB;

/** Which uniqueness rule a unique violation (23505) on creating a squad names. */
const UNIQUE_RULES: Record<string, 'idTaken' | 'inviteCodeTaken' | undefined> = {
  squads_pkey: 'idTaken',
  squads_invite_code_key: 'inviteCodeTaken',
};

const Constraint = z.object({ constraint: z.string() });

/** The squad store on Postgres (`supabase/migrations`). */
export function createPostgresSquadStore(db: Kysely<SquadTables>): SquadStore {
  /** The rows as squads, each with its members, earliest joined first, in the rows' order. */
  async function withMembers(rows: readonly Selectable<Squads>[]): Promise<Squad[]> {
    if (rows.length === 0) return [];
    const memberRows = await db
      .selectFrom('squad_members')
      .select(['squad_id', 'member_id', 'joined_at'])
      .where(
        'squad_id',
        'in',
        rows.map((row) => row.id),
      )
      .orderBy('joined_at')
      .orderBy('member_id')
      .execute();
    return rows.map((row) => {
      const members = memberRows
        .filter((member) => member.squad_id === row.id)
        .map((member) => ({
          member: MemberId.parse(member.member_id),
          joinedAt: member.joined_at,
        }));
      return {
        id: SquadId.parse(row.id),
        name: SquadName.parse(row.name),
        inviteCode: InviteCode.parse(row.invite_code),
        createdAt: row.created_at,
        createdBy: row.created_by === null ? null : MemberId.parse(row.created_by),
        captain: captainOf(
          row.captain_id === null ? null : MemberId.parse(row.captain_id),
          members,
        ),
        members,
      };
    });
  }

  /**
   * Holds the squad still until the transaction ends, and reads its name, its captain as members
   * see it, and its members, the earliest joined first.
   */
  async function lockSquad(trx: Transaction<SquadTables>, squad: SquadId) {
    const row = await trx
      .selectFrom('squads')
      .select(['name', 'captain_id'])
      .where('id', '=', squad)
      .forUpdate()
      .executeTakeFirst();
    if (row === undefined) return undefined;
    const members = (
      await trx
        .selectFrom('squad_members')
        .select(['member_id', 'joined_at'])
        .where('squad_id', '=', squad)
        .orderBy('joined_at')
        .orderBy('member_id')
        .execute()
    ).map((member) => ({ member: MemberId.parse(member.member_id), joinedAt: member.joined_at }));
    const stored = row.captain_id === null ? null : MemberId.parse(row.captain_id);
    return { name: row.name, stored, captain: captainOf(stored, members), members };
  }

  /** Saves the squad's name and captain, with its entry in the log. */
  async function saveSettings(
    trx: Transaction<SquadTables>,
    change: {
      readonly squad: SquadId;
      readonly actor: MemberId;
      readonly kind: 'renamed' | 'captainChanged';
      readonly name: string;
      readonly captain: MemberId | null;
    },
  ) {
    await trx
      .updateTable('squads')
      .set({ name: change.name, captain_id: change.captain })
      .where('id', '=', change.squad)
      .execute();
    await trx
      .insertInto('squad_events')
      .values({
        squad_id: change.squad,
        actor_id: change.actor,
        kind: change.kind,
        name: change.name,
        captain_id: change.captain,
      })
      .execute();
  }

  /** Takes a member out, with the log's entry, and hands on a captaincy they held. */
  async function takeOut(
    trx: Transaction<SquadTables>,
    {
      squad,
      member,
      kind,
      actor,
    }: {
      readonly squad: SquadId;
      readonly member: MemberId;
      readonly kind: 'left' | 'removed';
      readonly actor: MemberId;
    },
  ) {
    const before = await lockSquad(trx, squad);
    if (before?.members.some((each) => each.member === member) !== true) return false;
    await trx
      .deleteFrom('squad_members')
      .where('squad_id', '=', squad)
      .where('member_id', '=', member)
      .execute();
    await trx
      .insertInto('squad_membership_events')
      .values({ squad_id: squad, member_id: member, kind, actor_id: actor })
      .execute();
    const left = before.members.filter((each) => each.member !== member);
    const captain = captainOf(before.captain === member ? null : before.captain, left);
    if (captain !== before.stored) {
      await saveSettings(trx, { squad, actor, kind: 'captainChanged', name: before.name, captain });
    }
    return true;
  }

  /** Runs `change` if `actor` captains the squad now. */
  async function asCaptain(
    { squad, actor }: { readonly squad: SquadId; readonly actor: MemberId },
    change: (
      trx: Transaction<SquadTables>,
      now: NonNullable<Awaited<ReturnType<typeof lockSquad>>>,
    ) => Promise<CaptainOutcome>,
  ): Promise<CaptainOutcome> {
    return db.transaction().execute(async (trx) => {
      const now = await lockSquad(trx, squad);
      if (now?.captain !== actor) return 'notCaptain';
      return change(trx, now);
    });
  }

  /**
   * Holds this member's squad count still until the transaction ends, so two creates or joins at
   * once can't both see room for one more squad. A member may have no row of their own to lock
   * (a profile comes later), so this locks a number made from their id.
   */
  async function lockMember(trx: Transaction<SquadTables>, member: MemberId) {
    await sql`select pg_advisory_xact_lock(hashtextextended(${`squad-member:${member}`}, 0))`.execute(
      trx,
    );
  }

  async function squadCount(trx: Transaction<SquadTables>, member: MemberId) {
    const { count } = await trx
      .selectFrom('squad_members')
      .select((eb) => eb.fn.countAll<string>().as('count'))
      .where('member_id', '=', member)
      .executeTakeFirstOrThrow();
    return Number(count);
  }

  return {
    async find(id) {
      const rows = await db.selectFrom('squads').selectAll().where('id', '=', id).execute();
      const [squad] = await withMembers(rows);
      return squad;
    },

    async findByInviteCode(code) {
      const rows = await db
        .selectFrom('squads')
        .selectAll()
        .where('invite_code', '=', code)
        .execute();
      const [squad] = await withMembers(rows);
      return squad?.members.length === 0 ? undefined : squad;
    },

    async squadsOf(member) {
      const rows = await db
        .selectFrom('squads')
        .innerJoin('squad_members', 'squad_members.squad_id', 'squads.id')
        .selectAll('squads')
        .where('squad_members.member_id', '=', member)
        .orderBy('squad_members.joined_at')
        .orderBy('squads.id')
        .execute();
      return withMembers(rows);
    },

    async squadIdsOf(member) {
      const rows = await db
        .selectFrom('squad_members')
        .select('squad_id')
        .where('member_id', '=', member)
        .execute();
      return new Set(rows.map((row) => SquadId.parse(row.squad_id)));
    },

    async membersOf(squad) {
      const rows = await db
        .selectFrom('squad_members')
        .select('member_id')
        .where('squad_id', '=', squad)
        .orderBy('joined_at')
        .orderBy('member_id')
        .execute();
      return rows.map((row) => MemberId.parse(row.member_id));
    },

    async membersAt(squad, moment) {
      const rows = await db
        .selectFrom('squad_membership_events')
        .select(['member_id', 'kind'])
        .where('squad_id', '=', squad)
        .where('at', '<', moment)
        .orderBy('at')
        .orderBy('id')
        .execute();
      const members = new Map<string, true>();
      for (const { member_id: member, kind } of rows) {
        // A join moves the member to the end: the order they last joined in.
        members.delete(member);
        if (kind === 'joined') members.set(member, true);
      }
      return [...members.keys()].map((member) => MemberId.parse(member));
    },

    async membersOfAny(squads) {
      if (squads.length === 0) return new Set();
      const rows = await db
        .selectFrom('squad_members')
        .select('member_id')
        .distinct()
        .where('squad_id', 'in', squads)
        .execute();
      return new Set(rows.map((row) => MemberId.parse(row.member_id)));
    },

    async create({ id, name, inviteCode, creator }): Promise<CreateOutcome> {
      try {
        return await db.transaction().execute(async (trx): Promise<CreateOutcome> => {
          await lockMember(trx, creator);
          const taken = await trx
            .selectFrom('squads')
            .select('id')
            .where('id', '=', id)
            .executeTakeFirst();
          if (taken !== undefined) return { created: false, refused: 'idTaken' };
          if ((await squadCount(trx, creator)) >= SQUADS_PER_MEMBER) {
            return { created: false, refused: 'squadLimit' };
          }
          await trx
            .insertInto('squads')
            .values({ id, name, invite_code: inviteCode, created_by: creator, captain_id: creator })
            .execute();
          await trx
            .insertInto('squad_events')
            .values({ squad_id: id, actor_id: creator, kind: 'created', name, captain_id: creator })
            .execute();
          await trx
            .insertInto('squad_members')
            .values({ squad_id: id, member_id: creator })
            .execute();
          await trx
            .insertInto('squad_membership_events')
            .values({ squad_id: id, member_id: creator, kind: 'joined', actor_id: creator })
            .execute();
          return { created: true };
        });
      } catch (error) {
        const constraint = Constraint.safeParse(error).data?.constraint;
        const refused = constraint === undefined ? undefined : UNIQUE_RULES[constraint];
        if (hasErrorCode(error, '23505') && refused !== undefined)
          return { created: false, refused };
        throw error;
      }
    },

    async join(squad, member): Promise<JoinOutcome> {
      return db.transaction().execute(async (trx): Promise<JoinOutcome> => {
        // Always the member first, then the squad, so two joins never wait on each other in a circle.
        await lockMember(trx, member);
        await trx
          .selectFrom('squads')
          .select('id')
          .where('id', '=', squad)
          .forUpdate()
          .executeTakeFirstOrThrow();
        const members = await trx
          .selectFrom('squad_members')
          .select('member_id')
          .where('squad_id', '=', squad)
          .execute();
        if (members.length === 0) return 'ended';
        if (members.some((row) => row.member_id === member)) return 'alreadyMember';
        if ((await squadCount(trx, member)) >= SQUADS_PER_MEMBER) return 'squadLimit';
        if (members.length >= SQUAD_MEMBER_LIMIT) return 'squadFull';
        await trx
          .insertInto('squad_members')
          .values({ squad_id: squad, member_id: member })
          .execute();
        await trx
          .insertInto('squad_membership_events')
          .values({ squad_id: squad, member_id: member, kind: 'joined', actor_id: member })
          .execute();
        return 'joined';
      });
    },

    async leave(squad, member) {
      await db.transaction().execute(async (trx) => {
        await takeOut(trx, { squad, member, kind: 'left', actor: member });
      });
    },

    rename({ squad, actor, name }) {
      return asCaptain({ squad, actor }, async (trx, now) => {
        if (now.name === name) return 'unchanged';
        await saveSettings(trx, { squad, actor, kind: 'renamed', name, captain: now.captain });
        return 'changed';
      });
    },

    handCaptaincy({ squad, actor, to }) {
      return asCaptain({ squad, actor }, async (trx, now) => {
        if (!now.members.some(({ member }) => member === to)) return 'notMember';
        if (to === now.captain) return 'unchanged';
        await saveSettings(trx, {
          squad,
          actor,
          kind: 'captainChanged',
          name: now.name,
          captain: to,
        });
        return 'changed';
      });
    },

    remove({ squad, actor, member }) {
      return asCaptain({ squad, actor }, async (trx) =>
        (await takeOut(trx, { squad, member, kind: 'removed', actor })) ? 'changed' : 'unchanged',
      );
    },

    async scenePicks(squad) {
      const rows = await db
        .selectFrom('squad_scene_picks')
        .select([sql<string>`week_start::text`.as('week_start'), 'scene', 'picked_by', 'picked_at'])
        .where('squad_id', '=', squad)
        .orderBy('week_start')
        .execute();
      return rows.map((row) => ({
        week: SceneWeek.parse(row.week_start),
        scene: Scene.parse(row.scene),
        by: row.picked_by === null ? null : MemberId.parse(row.picked_by),
        at: row.picked_at,
      }));
    },

    async pickScene({ squad, week, scene, by }) {
      const saved = await db
        .insertInto('squad_scene_picks')
        .values({ squad_id: squad, week_start: week, scene, picked_by: by })
        .onConflict((oc) => oc.columns(['squad_id', 'week_start']).doNothing())
        .returning('scene')
        .executeTakeFirst();
      return saved === undefined ? 'taken' : 'picked';
    },
  };
}
