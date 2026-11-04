import type { ListedScene } from './domain/catalog.js';

/** Where the scenes are kept. */
export interface SceneStore {
  /** Every scene, retired ones too, in the picker's order. */
  list(): Promise<ListedScene[]>;
  /** Adds or replaces `scene`, with `order` every scene's id in their new order. */
  save(scene: ListedScene, order: readonly string[]): Promise<void>;
}
