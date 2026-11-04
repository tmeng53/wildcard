import { SceneEdit, type ListedScene, type Scenes, type ScenesAdmin } from '@wildcard/scenes';
import { z } from 'zod';

import { adminTool } from '../admin-tool.js';

// The scenes squads train on: each one's names, colours and place in the picker, and the switch a
// limited one (the winter 雪场) follows. A change reaches apps through the public
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
      'zh-Hant, colours (signature, onSignature, wash, text, floor), offered, and switchId (a ' +
      'limited scene is open only while that switch is on, see get_switches; none for all year). ' +
      'A squad on a scene that closes goes back to the gym the next week.',
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
      'out is not kept, and leaving out switchId opens it all year). A new scene needs its art in ' +
      'the app; builds without it show the gym. Set offered to false to retire one. Apps see it ' +
      'within a minute. Returns the scenes now.',
    changes: true,
    input: SceneEdit,
    run: async (edit) => shown(await scenes.putScene(edit)),
  });
}

export const sceneTools = (deps: SceneToolDependencies) => [getScenes(deps), putScene(deps)];
