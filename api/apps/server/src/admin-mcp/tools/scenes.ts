import {
  SceneEdit,
  SceneWindowEdit,
  type ListedScene,
  type Scenes,
  type ScenesAdmin,
} from '@wildcard/scenes';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The scenes squads train on: each one's names, colours and place in the picker, and the days a
// limited one (the winter 雪场) is open every year. A change reaches apps through the public
// catalog within a minute; the art ships with the app, which shows the gym for a scene it has no
// art for. Scenes are retired, never deleted, and keep their ids.

interface SceneToolDependencies {
  readonly scenes: Scenes & ScenesAdmin;
}

const shown = (scenes: readonly ListedScene[]) => ({ version: 1, scenes: [...scenes] });

/** `get_scenes`: every scene now. */
export function getScenes({ scenes }: SceneToolDependencies) {
  return adminTool({
    name: 'get_scenes',
    title: 'Read the scenes',
    description:
      'Shows every scene squads can pick, in the picker’s order: id, names in zh-Hans, en and ' +
      'zh-Hant, colours (signature, onSignature, wash, text, floor), offered, and window (the ' +
      'days of every year a limited scene is open, MM-DD to MM-DD, New York time; none for all ' +
      'year). A squad on a scene that closes goes back to the gym the next week.',
    changes: false,
    input: z.strictObject({}),
    run: async () => shown(await scenes.list()),
  });
}

/** `put_scene`: adds a scene, or replaces one whole. */
export function putScene({ scenes }: SceneToolDependencies) {
  return adminTool({
    name: 'put_scene',
    title: 'Add or change a scene',
    description:
      'Adds a scene, or replaces every field of one (read it with get_scenes first: a field left ' +
      'out is not kept, and leaving out window opens it all year). A new scene needs its art in ' +
      'the app; builds without it show the gym. Set offered to false to retire one. Apps see it ' +
      'within a minute. Returns the scenes now.',
    changes: true,
    input: SceneEdit,
    run: async (edit) => shown(await scenes.putScene(edit)),
  });
}

/** `set_scene_window`: changes when a limited scene is open. */
export function setSceneWindow({ scenes }: SceneToolDependencies) {
  return adminTool({
    name: 'set_scene_window',
    title: 'Set when a scene is open',
    description:
      'Changes only the days of every year a scene is open, such as the winter 雪场 from 11-15 ' +
      'to 03-31 (MM-DD, both included, New York time; the end may come before the start, over ' +
      'New Year). Null opens it all year. A week counts by its Monday: the picker offers the ' +
      'scene for a week whose Monday is in the window, and a squad on it goes back to the gym ' +
      'the first week after. Returns the scenes now.',
    changes: true,
    input: SceneWindowEdit,
    run: async (edit) => shown(await scenes.setWindow(edit)),
  });
}

export const sceneTools = (deps: SceneToolDependencies) => [
  getScenes(deps),
  putScene(deps),
  setSceneWindow(deps),
];
