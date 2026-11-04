import { AppError } from '@wildcard/errors';

/** Thrown when an admin changes a scene the list doesn't have. */
export class SceneNotFoundError extends AppError {
  override readonly name = 'SceneNotFoundError';
  readonly reason = 'SCENE_NOT_FOUND';
  readonly status = 'NOT_FOUND';

  constructor(readonly scene: string) {
    super(`There is no scene ${scene}.`);
  }
}
