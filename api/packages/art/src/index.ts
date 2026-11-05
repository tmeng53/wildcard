// @wildcard/art: the art apps download (character pieces, props, moves, scene pictures), so
// new art reaches installed apps without a release. Files live in a public bucket under their
// SHA-256; the database says which stands at each path of the app's art tree.

export { createPostgresArtStore, type ArtTables } from './adapters/postgres-art-store.js';
export {
  ArtEdit,
  ArtFileEdit,
  ArtPath,
  ArtRetirement,
  RigVersion,
  Sha256,
  checkArt,
  type ArtFile,
  type ArtManifest,
} from './domain/art.js';
export { ArtFileMissingError, ArtRefusedError, ArtStorageUnavailableError } from './errors.js';
export type { ArtBlobs, ArtStore } from './ports.js';
export { createArt, type Art, type ArtAdmin } from './use-cases/art.js';
