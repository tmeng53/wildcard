// `pnpm db-types [--verify]`: rewrites each module's Kysely table types from the database at
// DATABASE_URL (local Supabase, after `supabase db reset`). With `--verify` it only checks they
// are current. Each module owns its tables, so each gets its own file.
import { execFileSync } from 'node:child_process';

const MODULES = [
  {
    tables: ['check_ins', 'check_in_squads', 'check_in_photos', 'squad_members'],
    out: 'packages/check-ins/src/adapters/tables.ts',
  },
  { tables: ['admins', 'admin_actions'], out: 'packages/admins/src/adapters/tables.ts' },
];

for (const { tables, out } of MODULES) {
  execFileSync(
    'kysely-codegen',
    [
      '--dialect',
      'postgres',
      '--date-parser',
      'string',
      '--include-pattern',
      `public.(${tables.join('|')})`,
      '--out-file',
      out,
      ...process.argv.slice(2),
    ],
    { stdio: 'inherit' },
  );
}
