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
const svg = (inner: string) =>
  text(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 320">${inner}</svg>`);
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
    expect(refusal(path, text('<svg><path d="M0 0"/></svg>'))).toBe(
      'the <svg> needs a viewBox at 0 0',
    );
    expect(refusal(path, text('<!DOCTYPE svg><svg viewBox="0 0 1 1"/>'))).toBe(
      'it must start with <svg>',
    );
  });

  it('reads each value as the app’s parser does', () => {
    const path = ArtPath.parse('avatar/art/hat/beanie/crown.svg');
    expect(refusal(path, svg('<circle r="1" fill="red"/>'))).toBe(
      'fill="red" on <circle> isn’t read',
    );
    expect(refusal(path, svg('<circle r="1" style="transform:rotate(9deg)"/>'))).toBe(
      'transform on <circle> isn’t read',
    );
    expect(refusal(path, svg('<circle r="1" style="fill:#FFF;stroke-width:2"/>'))).toBeUndefined();
    expect(refusal(path, svg('<circle r="1" fill=">" onload="x"/>'))).toBe(
      'fill=">" on <circle> isn’t read',
    );
    expect(refusal(path, svg('<circle r="one"/>'))).toBe('r="one" on <circle> isn’t read');
    expect(refusal(path, svg('<g opacity="0.5"/>'))).toBe('opacity on <g> isn’t read');
    expect(refusal(path, svg('<path d="L0 0 1 1"/>'))).toBe('d="L0 0 1 1" on <path> isn’t read');
    expect(refusal(path, svg('<circle cx="1"/>'))).toBe('<circle> needs r');
    expect(refusal(path, svg('<rect width="1"/>'))).toBe('<rect> needs height');
    expect(refusal(path, svg('<path fill="#000"/>'))).toBe('<path> needs d');
    expect(refusal(path, svg('<circle r="1"></g>'))).toBe('</g> closes no <g>');
    expect(refusal(path, svg('<circle r="1" r="2"/>'))).toBe('<circle> names an attribute twice');
    expect(refusal(path, svg('<circle r="1" stroke-dasharray="-1 2"/>'))).toBe(
      'stroke-dasharray="-1 2" on <circle> isn’t read',
    );
    expect(refusal(path, svg('<circle r=1/>'))).toBe(
      'every tag is whole, with its attributes quoted',
    );
    expect(refusal(path, text('<svg viewBox="5 5 10 10"><path d="M0 0"/></svg>'))).toBe(
      'viewBox="5 5 10 10" on <svg> isn’t read',
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
