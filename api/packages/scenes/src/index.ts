// @wildcard/scenes: the scenes a squad trains on (names, colours, order, and the days a limited
// one like the winter 雪场 is open), kept in the database so they change without an app release.

export { createPostgresSceneStore, type SceneTables } from './adapters/postgres-scene-store.js';
export {
  isOpen,
  SceneId,
  type ListedScene,
  type LocalizedNames,
  type SceneColors,
  type SwitchOn,
} from './domain/catalog.js';
export { SceneEdit } from './domain/edits.js';
export type { SceneStore, SwitchStates } from './ports.js';
export { createScenes, type Scenes, type ScenesAdmin } from './use-cases/scenes.js';
