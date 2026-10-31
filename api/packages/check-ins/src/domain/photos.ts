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

/** The most pixels a photo's side may claim: well past what the app uploads (1080). */
export const PHOTO_SIDE_MAX = 10_000;

/**
 * A photo's size in pixels, as the app prepared it, so a feed lays the photo out at its shape
 * before it loads. The server only checks the shape; it never opens the file.
 */
export const PhotoSize = z
  .strictObject({
    width: z.int().min(1).max(PHOTO_SIDE_MAX),
    height: z.int().min(1).max(PHOTO_SIDE_MAX),
  })
  .meta({
    id: 'PhotoSize',
    description: 'Its width and height in pixels. Missing on photos saved without one.',
  });
export type PhotoSize = z.infer<typeof PhotoSize>;

/**
 * One photo of a check-in, as `POST /photo-uploads` named it, with its size in pixels. Photos
 * saved before sizes were sent have none.
 */
export const PhotoRef = z
  .strictObject({
    path: PhotoPath,
    size: PhotoSize.optional(),
  })
  .meta({ id: 'PhotoRef' });
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
