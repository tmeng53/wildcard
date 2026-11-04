import { isOwnPhoto, type PhotoPath } from '../domain/photos.js';
import { PhotoNotUploadedError, PhotoNotYoursError } from '../errors.js';
import type { PhotoFiles } from '../ports.js';

/** Each photo is in the member's own folder and already uploaded. */
export async function checkPhotos(
  files: PhotoFiles,
  photos: { readonly member: string; readonly paths: readonly PhotoPath[] },
): Promise<void> {
  const { member, paths } = photos;
  const notYours = paths.find((path) => !isOwnPhoto(path, member));
  if (notYours !== undefined) throw new PhotoNotYoursError(notYours);
  const uploaded = await Promise.all(paths.map((path) => files.exists(path)));
  const missing = paths.find((_path, index) => uploaded[index] !== true);
  if (missing !== undefined) throw new PhotoNotUploadedError(missing);
}
