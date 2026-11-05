import { createHash } from 'node:crypto';

import {
  CONTENT_TYPES,
  checkArt,
  kindOf,
  type ArtEdit,
  type ArtManifest,
  type ArtPath,
  type ArtRetirement,
} from '../domain/art.js';
import { ArtFileMissingError, ArtRefusedError } from '../errors.js';
import type { ArtBlobs, ArtStore } from '../ports.js';

/** The art apps download, for the public catalog. */
export interface Art {
  /** What stands now, with where apps download each file from. */
  manifest(): Promise<ArtManifest & { readonly baseUrl: URL }>;
}

/** Changing the art, for admins. */
export interface ArtAdmin extends Art {
  /** Checks, stores and puts every file of `edit` as one generation; answers with the art now. */
  put(edit: ArtEdit, admin: string): Promise<ArtManifest>;
  /** Takes `retirement.paths` back to the bundled files; answers with the art now. */
  retire(retirement: ArtRetirement, admin: string): Promise<ArtManifest>;
  /** A URL to upload one file of type `extension` with SHA-256 `sha256` to. */
  uploadUrl(sha256: string, extension: 'svg' | 'json' | 'png'): Promise<URL>;
}

const sha256Of = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const nameOf = (sha256: string, path: ArtPath) => `${sha256}.${kindOf(path)}`;

export function createArt(deps: { readonly store: ArtStore; readonly blobs: ArtBlobs }): ArtAdmin {
  const { store, blobs } = deps;
  return {
    async manifest() {
      return { ...(await store.manifest()), baseUrl: blobs.publicBase };
    },

    async put({ files, rigVersion }, admin) {
      // Every file is checked and stored before any row is written, so a refusal changes nothing.
      const changes = await Promise.all(
        files.map(async (file) => {
          let bytes: Uint8Array;
          if ('text' in file) {
            if (kindOf(file.path) === 'png') {
              throw new ArtRefusedError(
                file.path,
                'a PNG goes up with art_upload_url, then by sha256',
              );
            }
            bytes = new TextEncoder().encode(file.text);
          } else {
            const uploaded = await blobs.get(nameOf(file.sha256, file.path));
            if (uploaded === undefined) throw new ArtFileMissingError(file.sha256);
            bytes = uploaded;
          }
          checkArt(file.path, bytes);
          const sha256 = sha256Of(bytes);
          if ('sha256' in file && sha256 !== file.sha256) {
            throw new ArtRefusedError(file.path, 'the uploaded file’s SHA-256 isn’t the one given');
          }
          if ('text' in file)
            await blobs.put({
              name: nameOf(sha256, file.path),
              bytes,
              contentType: CONTENT_TYPES[kindOf(file.path)],
            });
          return { path: file.path, file: { sha256, size: bytes.byteLength, rigVersion } };
        }),
      );
      // A file already standing at its path, the same bytes for the same rig, is no change.
      const standing = new Map((await store.manifest()).files.map((file) => [file.path, file]));
      const changed = changes.filter(({ path, file }) => {
        const now = standing.get(path);
        return now?.sha256 !== file.sha256 || now.rigVersion !== file.rigVersion;
      });
      if (changed.length > 0) await store.record(changed, admin);
      return store.manifest();
    },

    async retire({ paths }, admin) {
      const standing = new Set((await store.manifest()).files.map(({ path }) => path));
      const changes = paths.filter((path) => standing.has(path)).map((path) => ({ path }));
      if (changes.length > 0) await store.record(changes, admin);
      return store.manifest();
    },

    uploadUrl: (sha256, extension) => blobs.uploadUrl(`${sha256}.${extension}`),
  };
}
