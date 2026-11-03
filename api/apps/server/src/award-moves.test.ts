import { readFileSync, readdirSync } from 'node:fs';

import { sql } from 'kysely';
import { afterAll, describe, expect, it } from 'vitest';
import { z } from 'zod';

import { createDatabase } from './adapters/postgres.js';
import { config } from './test-kit/local-supabase.js';

// The weekly awards pick their moves from the ones `weekly_award_settings.moves` describes, so
// a move offers itself once it has a description. The app's character art is where moves come
// from (AvatarArt's `NamedMove`): every move it can play for an award must be described (a
// migration adds the line), and nothing may be described that the app only plays as its cheer.
const art = new URL('../../../../ios/Packages/Avatar/Sources/AvatarArt/', import.meta.url);

/** The moves AvatarArt's `NamedMove` plays by their own id: `cheer` and `flat` (躺平). */
function ownMoves(): string[] {
  const source = readFileSync(new URL('NamedMoves.swift', art), 'utf8');
  return [...source.matchAll(/\bid == "([a-z-]+)"/gu)].map((match) => match[1] ?? '');
}

/** The moves every character shares: the cases of AvatarArt's `Move`. */
function sharedMoves(): string[] {
  const source = readFileSync(new URL('Move.swift', art), 'utf8');
  const body = /public enum Move\b[^{]*\{([\s\S]*?)\n\}/u.exec(source)?.[1] ?? '';
  return [...body.matchAll(/^\s+case (\w+)\s*$/gmu)].map((match) => match[1] ?? '');
}

/** 动态's reaction moves: `moves/reactions/<id>.json`. */
function reactionMoves(): string[] {
  return readdirSync(new URL('Placeholder/moves/reactions/', art))
    .filter((name) => name.endsWith('.json'))
    .map((name) => name.slice(0, -'.json'.length));
}

/** Each sport kit's move, by kit id: `kits.json`. */
function kitMoves(): string[] {
  const Kits = z.object({ kits: z.array(z.object({ id: z.string() })) });
  return Kits.parse(
    JSON.parse(readFileSync(new URL('Placeholder/kits.json', art), 'utf8')),
  ).kits.map(({ id }) => id);
}

const db = createDatabase(config.databaseUrl);
afterAll(() => db.destroy());

describe('the award moves', () => {
  it('describe every move the app can play for an award, and only those', async () => {
    const appMoves = new Set([...ownMoves(), ...sharedMoves(), ...reactionMoves(), ...kitMoves()]);
    expect(appMoves.size).toBeGreaterThan(20);
    const { rows } = await sql<{
      moves: Record<string, string>;
    }>`select moves from public.weekly_award_settings`.execute(db);
    const described = new Set(Object.keys(rows[0]?.moves ?? {}));
    const missing = [...appMoves].filter((move) => !described.has(move)).sort();
    expect(missing, 'moves with art but no description: add them in a migration').toStrictEqual([]);
    const stray = [...described].filter((move) => !appMoves.has(move)).sort();
    expect(stray, 'moves described that the app has no art for').toStrictEqual([]);
  });
});
