import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

import { describe, expect, it } from 'vitest';

import { ArtRefusedError } from '../errors.js';
import { ArtPath, checkArt } from './art.js';

// The art the app bundles today, at the paths its downloads use.
const repo = join(import.meta.dirname, '../../../../..');
const trees = [
  { root: join(repo, 'ios/Packages/Avatar/Sources/AvatarArt/Placeholder'), prefix: 'avatar' },
  { root: join(repo, 'ios/Packages/Avatar/Sources/AvatarArt/Coaches'), prefix: 'coaches' },
  { root: join(repo, 'ios/Packages/CheckIn/Sources/CheckInUI/Resources/Scenes'), prefix: 'scenes' },
];
const filesUnder = (folder: string): string[] =>
  readdirSync(folder).flatMap((name) => {
    const path = join(folder, name);
    return statSync(path).isDirectory() ? filesUnder(path) : [path];
  });
const bundled = trees.flatMap(({ root, prefix }) =>
  filesUnder(root)
    .filter((path) => /\.(svg|json|png)$/.test(path))
    .map((path) => ({ path: `${prefix}/${relative(root, path)}`, file: path })),
);

const text = (svg: string) => new TextEncoder().encode(svg);
const refusal = (path: string, bytes: Uint8Array) => {
  try {
    checkArt(ArtPath.parse(path), bytes);
  } catch (error) {
    if (error instanceof ArtRefusedError) return error.why;
    throw error;
  }
  return undefined;
};

describe('checkArt', () => {
  it('passes every file the app bundles, at its path', () => {
    expect(bundled.length).toBeGreaterThan(400);
    const refused = bundled.flatMap(({ path, file }) => {
      const parsed = ArtPath.safeParse(path);
      if (!parsed.success) return [`${path}: not an art path`];
      const why = refusal(path, readFileSync(file));
      return why === undefined ? [] : [`${path}: ${why}`];
    });
    expect(refused).toEqual([]);
  });

  it('refuses what the app can’t draw', () => {
    const svg = (inner: string) =>
      text(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">${inner}</svg>`);
    const path = 'avatar/art/hat/beanie/crown.svg';
    expect(refusal(path, svg('<path d="M0 0L1 1" fill="#FFFFFF"/>'))).toBeUndefined();
    expect(refusal(path, svg('<script>alert(1)</script>'))).toBe('<script> isn’t drawn');
    expect(refusal(path, svg('<path d="M0 0" onclick="x"/>'))).toBe('onclick on <path> isn’t read');
    expect(refusal(path, svg('<path d="M0 0" transform="rotate(4)"/>'))).toBe(
      'transform on <path> isn’t read',
    );
    expect(refusal(path, svg('<path d="M0 0 A 4 4 0 0 1 8 8"/>'))).toBe(
      'paths have no arcs (outline them)',
    );
    expect(refusal(path, svg('<image href="https://example.com/x.png"/>'))).toBe(
      '<image> isn’t drawn',
    );
    expect(refusal(path, text('<svg><path d="M0 0"/></svg>'))).toBe('the <svg> needs a viewBox');
    expect(refusal(path, text('<!DOCTYPE svg><svg viewBox="0 0 1 1"/>'))).toBe(
      'it must start with <svg>',
    );
  });

  it('wants JSON with a version and real PNGs', () => {
    expect(refusal('avatar/moves/ski.json', text('{"version":1,"tracks":[]}'))).toBeUndefined();
    expect(refusal('avatar/moves/ski.json', text('{"tracks":[]}'))).toBe(
      'JSON needs a top-level integer version',
    );
    expect(refusal('avatar/moves/ski.json', text('[1]'))).toBe('JSON must be an object');
    expect(refusal('scenes/ski-day@3x.png', text('not a png'))).toBe('not a PNG');
  });

  it('keeps paths inside the art tree', () => {
    expect(ArtPath.safeParse('avatar/../../etc/passwd.json').success).toBe(false);
    expect(ArtPath.safeParse('web/index.svg').success).toBe(false);
    expect(ArtPath.safeParse('avatar/art/top/x/torso.js').success).toBe(false);
    expect(ArtPath.safeParse('avatar/art/top/warmup-tee/armL.svg').success).toBe(true);
  });
});
