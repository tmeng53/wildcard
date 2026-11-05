import type { ArtFile, ArtManifest, ArtPath } from './domain/art.js';

/** Which file stands at each path: every change kept, the newest per path standing. */
export interface ArtStore {
  manifest(): Promise<ArtManifest>;
  /**
   * Keeps `changes` by `admin` as one generation: a file at a path, or the path back to the
   * bundled file (`file` undefined).
   */
  record(
    changes: readonly { readonly path: ArtPath; readonly file?: Omit<ArtFile, 'path'> }[],
    admin: string,
  ): Promise<void>;
}

/** The public bucket the files live in, each named `<sha256>.<extension>`. */
export interface ArtBlobs {
  /** Keeps `bytes` under `name`; one already there is the same file. */
  put(file: {
    readonly name: string;
    readonly bytes: Uint8Array;
    readonly contentType: string;
  }): Promise<void>;
  /** The file under `name`, or undefined when nothing was uploaded there. */
  get(name: string): Promise<Uint8Array | undefined>;
  /** A URL an admin's tool uploads one file to, under `name`, for a while. */
  uploadUrl(name: string): Promise<URL>;
  /** Where apps download the file under `name` from. */
  readonly publicBase: URL;
}
