import { z } from 'zod';

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

/**
 * Roughly where a member is: a 0.1° cell (about 11 km), never finer, whatever the phone sends.
 * Only for looking up the weather there; squadmates and the model never see it.
 */
export interface Place {
  readonly latitude: number;
  readonly longitude: number;
}

/** A place as the phone sends it, which may be finer than we keep. */
export const Coordinates = z.strictObject({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
});

/** The 0.1° cell `coordinates` are in, which is all of a place we keep. */
export function cellOf({ latitude, longitude }: Place): Place {
  const round = (value: number) => Math.round(value * 10) / 10;
  // 180.0 and -180.0 are the same meridian; keep one.
  const lon = round(longitude);
  return { latitude: round(latitude), longitude: lon === 180 ? -180 : lon };
}
