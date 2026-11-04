import { z } from '@hono/zod-openapi';

/**
 * The scenes builds before the scenes list knew (until 2026-11): `scene` fields name only these,
 * so an installed build reads them; a newer scene is sent there as the gym, and by its id in the
 * `sceneId` field beside it.
 */
export const LEGACY_SCENES = ['track', 'pool', 'gym', 'tennis', 'climbing'] as const;
export const LegacyScene = z.enum(LEGACY_SCENES);

/** `scene` as builds before the scenes list read it: the gym for a scene they don't know. */
export function legacyScene(scene: string): (typeof LEGACY_SCENES)[number] {
  const known = LegacyScene.safeParse(scene);
  return known.success ? known.data : 'gym';
}
