import { hasErrorCode } from '@wildcard/errors';
import { sql, type Kysely, type Selectable, type Transaction } from 'kysely';
import { z } from 'zod';

import { InviteCode } from '../domain/invite-code.js';
import {
  MemberId,
  SQUAD_MEMBER_LIMIT,
  SQUADS_PER_MEMBER,
  SquadId,
  SquadName,
  type Squad,
} from '../domain/squad.js';
import type { CreateOutcome, JoinOutcome, SquadStore } from '../ports.js';
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
    return rows.map((row) => ({
      id: SquadId.parse(row.id),
      name: SquadName.parse(row.name),
      inviteCode: InviteCode.parse(row.invite_code),
      createdAt: row.created_at,
      createdBy: row.created_by === null ? null : MemberId.parse(row.created_by),
      members: memberRows
        .filter((member) => member.squad_id === row.id)
        .map((member) => ({
          member: MemberId.parse(member.member_id),
          joinedAt: member.joined_at,
        })),
    }));
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
      return squad;
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
            .values({ id, name, invite_code: inviteCode, created_by: creator })
            .execute();
          await trx
            .insertInto('squad_members')
            .values({ squad_id: id, member_id: creator })
            .execute();
          await trx
            .insertInto('squad_membership_events')
            .values({ squad_id: id, member_id: creator, kind: 'joined' })
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
        if (members.some((row) => row.member_id === member)) return 'alreadyMember';
        if ((await squadCount(trx, member)) >= SQUADS_PER_MEMBER) return 'squadLimit';
        if (members.length >= SQUAD_MEMBER_LIMIT) return 'squadFull';
        await trx
          .insertInto('squad_members')
          .values({ squad_id: squad, member_id: member })
          .execute();
        await trx
          .insertInto('squad_membership_events')
          .values({ squad_id: squad, member_id: member, kind: 'joined' })
          .execute();
        return 'joined';
      });
    },

    async leave(squad, member) {
      // One statement, so a membership never goes without its entry in the log, or twice.
      await db
        .with('left', (eb) =>
          eb
            .deleteFrom('squad_members')
            .where('squad_id', '=', squad)
            .where('member_id', '=', member)
            .returning(['squad_id', 'member_id']),
        )
        .insertInto('squad_membership_events')
        .columns(['squad_id', 'member_id', 'kind'])
        .expression((eb) =>
          eb.selectFrom('left').select(['squad_id', 'member_id', sql.lit('left').as('kind')]),
        )
        .execute();
    },
  };
}
