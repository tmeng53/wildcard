import { z } from 'zod';

/**
 * A check-in photo's name in storage: `<member id>/<photo id>`, both UUIDs. The first part is
 * the folder of the member who uploaded it; the server picks both parts, never the app.
 */
export const PhotoPath = z
  .string()
  .regex(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
  )
  .brand<'PhotoPath'>();
export type PhotoPath = z.infer<typeof PhotoPath>;

/** Whether a photo is in this member's own folder: the only photos they may use or delete. */
export function isOwnPhoto(path: PhotoPath, member: string): boolean {
  return path.startsWith(`${member}/`);
}

/** One photo of a check-in, as `POST /photo-uploads` named it. */
export const PhotoRef = z.strictObject({ path: PhotoPath }).meta({ id: 'PhotoRef' });
export type PhotoRef = z.infer<typeof PhotoRef>;

/** A check-in's photos: 1 to 3, no repeats, in the member's order. The first is the cover. */
export const Photos = z
  .array(PhotoRef)
  .min(1)
  .max(3)
  .refine((photos) => new Set(photos.map(({ path }) => path)).size === photos.length, {
    message: 'Must not list a photo twice',
  })
  .meta({ description: '1 to 3 photos, the cover first. Leave it out for none.' });
