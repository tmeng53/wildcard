import { PlaceKey } from '@wildcard/place-ids';
import { z } from 'zod';

// The ids the places module speaks in: a member, and a place as every module addresses it.

export const MemberId = z.uuid().brand<'MemberId'>();
export type MemberId = z.infer<typeof MemberId>;

export { PlaceKey };
