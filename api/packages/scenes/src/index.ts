// @wildcard/scenes: the scenes a squad trains on (names, colours, order, and the days a limited
// one like the winter 雪场 is open), kept in the database so they change without an app release.

export { createPostgresSceneStore, type SceneTables } from './adapters/postgres-scene-store.js';
export {
  inWindow,
  isOpen,
  SceneId,
  type ListedScene,
  type LocalizedNames,
  type SceneColors,
  type SceneWindow,
} from './domain/catalog.js';
export { SceneEdit, SceneWindowEdit } from './domain/edits.js';
export { SceneNotFoundError } from './errors.js';
export type { SceneStore } from './ports.js';
export { createScenes, type Scenes, type ScenesAdmin } from './use-cases/scenes.js';
