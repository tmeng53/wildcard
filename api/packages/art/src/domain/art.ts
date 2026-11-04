import { z } from 'zod';

import { ArtRefusedError } from '../errors.js';

// The art the app downloads: files at paths of the app's art tree, each kept in the bucket under
// its content's SHA-256. Data only (App Store guideline 2.5.2): SVG in the art's subset,
// keyframe JSON and PNG. The app checks each file again with its own parser before it uses a
// generation, so this is the server's first line, not the only one.

/** A path in the app's art tree, as the app bundles it: `avatar/art/top/warmup-tee/torso.svg`. */
export const ArtPath = z
  .string()
  .regex(/^(avatar|coaches|scenes)(\/[A-Za-z0-9][A-Za-z0-9_@.-]{0,63}){1,6}\.(svg|json|png)$/)
  .refine((path) => !path.includes('..'), 'A path never leaves the art tree.')
  .brand<'ArtPath'>()
  .meta({
    description:
      'Where the file sits in the app’s art tree, the path the app bundles it at: avatar/… ' +
      'mirrors the character’s Placeholder folder (art/<slot>/<variant>/<part>.svg, moves/…, ' +
      'editor.json, kits.json), coaches/… the coaches’ characters (<coach id>/…), scenes/… the ' +
      'home scene pictures (<scene>-day@3x.png).',
    example: 'avatar/art/top/warmup-tee/torso.svg',
  });
export type ArtPath = z.infer<typeof ArtPath>;

export const Sha256 = z
  .string()
  .regex(/^[0-9a-f]{64}$/)
  .meta({ description: 'The file’s SHA-256, lowercase hex.' });

/** The lowest rig version the art needs; today's app draws version 1. */
export const RigVersion = z.int().min(1).max(1000);

export type ArtKind = 'svg' | 'json' | 'png';
export const CONTENT_TYPES: Record<ArtKind, string> = {
  svg: 'image/svg+xml',
  json: 'application/json',
  png: 'image/png',
};
export const MAX_BYTES: Record<ArtKind, number> = {
  svg: 256 * 1024,
  json: 256 * 1024,
  png: 2 * 1024 * 1024,
};

export const kindOf = (path: ArtPath): ArtKind => {
  const extension = path.slice(path.lastIndexOf('.') + 1);
  return extension === 'svg' || extension === 'json' ? extension : 'png';
};

/** A file that stands at a path now. */
export interface ArtFile {
  readonly path: ArtPath;
  readonly sha256: string;
  readonly size: number;
  readonly rigVersion: number;
}

/** What stands in the art tree now, and its generation (the newest change's number). */
export interface ArtManifest {
  readonly generation: number;
  readonly files: readonly ArtFile[];
}

/** One file to put: its text (SVG, JSON), or a file already uploaded, by its SHA-256. */
export const ArtFileEdit = z.union([
  z.strictObject({
    path: ArtPath,
    text: z.string().min(1).meta({ description: 'The whole file, for an .svg or .json path.' }),
  }),
  z.strictObject({
    path: ArtPath,
    sha256: Sha256.meta({
      description: 'A file uploaded with art_upload_url (any type; a .png has to go this way).',
    }),
  }),
]);
export type ArtFileEdit = z.infer<typeof ArtFileEdit>;

export const ArtEdit = z.strictObject({
  files: z
    .array(ArtFileEdit)
    .min(1)
    .max(100)
    .refine(
      (files) => new Set(files.map(({ path }) => path)).size === files.length,
      'Each path once.',
    )
    .meta({
      description:
        'Every file one change needs, together (a piece’s parts and the editor.json that hangs ' +
        'it on its rack): apps take all of them at once or none.',
    }),
  rigVersion: RigVersion.default(1).meta({
    description:
      'The lowest version of the app’s rig that can draw them; builds with an older rig leave ' +
      'them out. 1 unless the art uses rig parts a new release added.',
  }),
});
export type ArtEdit = z.infer<typeof ArtEdit>;

export const ArtRetirement = z.strictObject({
  paths: z
    .array(ArtPath)
    .min(1)
    .max(100)
    .meta({ description: 'Paths that go back to the file the app bundles (or to none).' }),
});
export type ArtRetirement = z.infer<typeof ArtRetirement>;

// SVG: what the app's parser reads (AvatarDomain's SVGArtwork), value by value, since a file that
// passes here and fails there would never reach a phone: the app leaves out what it can't read.
const ELEMENTS = new Set([
  'svg',
  'g',
  'path',
  'circle',
  'ellipse',
  'rect',
  'title',
  'desc',
  'metadata',
]);
const INERT = new Set(['id', 'class', 'xmlns', 'xmlns:xlink', 'version']);
const NUMBER = String.raw`[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?`;
const isNumber = (value: string) => new RegExp(`^\\s*${NUMBER}\\s*$`).test(value);
const isColor = (value: string) =>
  value === 'none' || /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(value);
const isNumbers = (value: string, count?: number) => {
  const numbers = value.trim().split(/[\s,]+/);
  return (count === undefined || numbers.length === count) && numbers.every(isNumber);
};
const VALUES: Record<string, (value: string) => boolean> = {
  d: (value) => /^[MmLlHhVvCcSsQqTtZz0-9eE.,+\-\s]*$/.test(value),
  cx: isNumber,
  cy: isNumber,
  r: isNumber,
  rx: isNumber,
  ry: isNumber,
  x: isNumber,
  y: isNumber,
  width: isNumber,
  height: isNumber,
  opacity: isNumber,
  'fill-opacity': isNumber,
  'stroke-opacity': isNumber,
  'stroke-width': isNumber,
  fill: isColor,
  stroke: isColor,
  'stroke-linecap': (value) => ['butt', 'round', 'square'].includes(value),
  'stroke-linejoin': (value) => ['miter', 'round', 'bevel'].includes(value),
  'stroke-dasharray': (value) => value === 'none' || isNumbers(value),
  viewBox: (value) => {
    const [x, y] = value
      .trim()
      .split(/[\s,]+/)
      .map(Number);
    return isNumbers(value, 4) && x === 0 && y === 0;
  },
};
// A whole start or end tag, with every attribute quoted: anything else isn't read the same way.
const TAG =
  /^<(\/?)([A-Za-z][\w:.-]*)((?:\s+[A-Za-z_:][\w:.-]*\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/;
const ATTRIBUTE = /([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;

const attributeProblem = (element: string, name: string, value: string): string | undefined => {
  if (INERT.has(name)) return undefined;
  if (name === 'opacity' && (element === 'svg' || element === 'g'))
    return `opacity on <${element}> isn’t read`;
  const valid = VALUES[name];
  if (valid === undefined) return `${name} on <${element}> isn’t read`;
  if (!valid(value)) return `${name}="${value}" on <${element}> isn’t read`;
  return undefined;
};

const svgProblem = (text: string): string | undefined => {
  const body = text.replace(/^\s*<\?xml[^>]*\?>/, '').replace(/<!--[\s\S]*?-->/g, '');
  if (!/^\s*<svg[\s>]/.test(body)) return 'it must start with <svg>';
  if (/<!|<\?|&/.test(body)) return 'no DOCTYPE, processing instructions or entities';
  let viewBox = false;
  for (let at = body.indexOf('<'); at !== -1; at = body.indexOf('<', at + 1)) {
    const tag = TAG.exec(body.slice(at));
    if (tag === null) return 'every tag is whole, with its attributes quoted';
    const [, closing = '', element = '', attributes = ''] = tag;
    if (!ELEMENTS.has(element)) return `<${element}> isn’t drawn`;
    if (closing !== '') continue;
    for (const [, name = '', double, single] of attributes.matchAll(ATTRIBUTE)) {
      const value = double ?? single ?? '';
      if (name === 'd' && /[Aa]/.test(value)) return 'paths have no arcs (outline them)';
      if (name === 'viewBox' && element === 'svg') viewBox = true;
      if (name !== 'style') {
        const problem = attributeProblem(element, name, value);
        if (problem !== undefined) return problem;
        continue;
      }
      for (const declaration of value.split(';')) {
        if (declaration.trim() === '') continue;
        const [key = '', ...rest] = declaration.split(':');
        if (rest.length !== 1) return `style="${value}" on <${element}> isn’t read`;
        const problem = attributeProblem(element, key.trim(), rest[0]?.trim() ?? '');
        if (problem !== undefined) return problem;
      }
    }
  }
  if (!viewBox) return 'the <svg> needs a viewBox at 0 0';
  return undefined;
};

const Versioned = z.looseObject({ version: z.int() });

const PNG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/**
 * Throws `ArtRefusedError` unless `bytes` is art the app can read at `path`: within its size,
 * SVG in the art's subset, JSON with a top-level `version`, or a PNG.
 */
export function checkArt(path: ArtPath, bytes: Uint8Array): void {
  const kind = kindOf(path);
  if (bytes.byteLength > MAX_BYTES[kind]) {
    throw new ArtRefusedError(path, `bigger than ${String(MAX_BYTES[kind] / 1024)} KB`);
  }
  if (kind === 'png') {
    if (!PNG.every((byte, index) => bytes[index] === byte))
      throw new ArtRefusedError(path, 'not a PNG');
    return;
  }
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new ArtRefusedError(path, 'not UTF-8 text');
  }
  if (kind === 'svg') {
    const problem = svgProblem(text);
    if (problem !== undefined) throw new ArtRefusedError(path, problem);
    return;
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ArtRefusedError(path, 'not JSON');
  }
  if (typeof json !== 'object' || json === null || Array.isArray(json)) {
    throw new ArtRefusedError(path, 'JSON must be an object');
  }
  if (!Versioned.safeParse(json).success) {
    throw new ArtRefusedError(path, 'JSON needs a top-level integer version');
  }
}
