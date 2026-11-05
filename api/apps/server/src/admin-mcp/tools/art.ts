import { ArtEdit, ArtRetirement, Sha256, type ArtAdmin, type ArtManifest } from '@wildcard/art';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The art apps download: character pieces, props, moves, scene pictures, and the lists that
// show them (editor.json, kits.json). Each file stands at a path of the app's art tree; a path
// nobody put a file at keeps the one the app bundles. Apps take a change on their next catalog
// read (within about a minute of opening the app) once every file of it is downloaded, with no
// release, as long as their rig can draw it. Every change is kept; nothing is deleted.

interface ArtToolDependencies {
  readonly art: ArtAdmin;
}

const shown = ({ generation, files }: ArtManifest) => ({
  version: 1,
  generation,
  files: files.map((file) => ({ ...file })),
});

/** `get_art`: every file apps download now. */
export function getArt({ art }: ArtToolDependencies) {
  return adminTool({
    name: 'get_art',
    title: 'Read the art apps download',
    description:
      'Shows every file put over the art the app bundles: path (avatar/… mirrors the ' +
      'character’s Placeholder folder in the repository, scenes/… the home scene pictures), ' +
      'sha256, size and rigVersion, and the generation (the newest change). Paths not listed ' +
      'use the bundled file. Read the repository’s Placeholder README for what each path does.',
    changes: false,
    input: z.strictObject({}),
    run: async () => shown(await art.manifest()),
  });
}

/** `art_upload_url`: where to upload one file before putting it. */
export function artUploadUrl({ art }: ArtToolDependencies) {
  return adminTool({
    name: 'art_upload_url',
    title: 'Get a URL to upload an art file',
    description:
      'For a PNG (scene pictures) or any file too big to send as text: answers a URL to PUT ' +
      'the file’s bytes to (with its content-type), good for about two hours. Then call ' +
      'put_art with the file’s path and sha256. Uploading alone changes nothing apps see.',
    changes: false,
    input: z.strictObject({
      sha256: Sha256,
      extension: z.enum(['svg', 'json', 'png']),
    }),
    run: async ({ sha256, extension }) => ({
      version: 1,
      uploadUrl: (await art.uploadUrl(sha256, extension)).href,
      contentType: { svg: 'image/svg+xml', json: 'application/json', png: 'image/png' }[extension],
    }),
  });
}

/** `put_art`: puts files at paths, all at once. */
export function putArt({ art }: ArtToolDependencies) {
  return adminTool({
    name: 'put_art',
    title: 'Add or replace art files',
    description:
      'Puts every file one change needs at its path, together: each as text (SVG, JSON) or by ' +
      'the sha256 of a file uploaded with art_upload_url. SVG must be the art’s subset (paths, ' +
      'circles, ellipses and rects with hex colors; no transforms, gradients, text, images or ' +
      'arcs), JSON must carry a top-level version. One refused file refuses them all. To show ' +
      'something new, also put the list that names it (avatar/editor.json for clothes and ' +
      'props, avatar/kits.json for a sport’s kit) with the rest. Returns the art now.',
    changes: true,
    input: ArtEdit,
    run: async (edit, { admin }) => shown(await art.put(edit, admin)),
  });
}

/** `retire_art`: takes paths back to the bundled files. */
export function retireArt({ art }: ArtToolDependencies) {
  return adminTool({
    name: 'retire_art',
    title: 'Take art back to the bundled files',
    description:
      'Takes each path back to the file the app bundles, or to none where the app bundles ' +
      'nothing there (a piece nobody can see). Use it to undo a put_art. Returns the art now.',
    changes: true,
    input: ArtRetirement,
    run: async (retirement, { admin }) => shown(await art.retire(retirement, admin)),
  });
}

export const artTools = (dependencies: ArtToolDependencies) => [
  getArt(dependencies),
  artUploadUrl(dependencies),
  putArt(dependencies),
  retireArt(dependencies),
];
