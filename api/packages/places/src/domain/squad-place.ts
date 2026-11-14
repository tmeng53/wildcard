import { nameText } from '@wildcard/typed-text';
import { z } from 'zod';

import type { MemberId } from './ids.js';

// Places a squad's members add themselves (Tracy, 2026-11-12), anywhere Apple Maps doesn't
// list: the whole squad sees them and may tag their own posts with them. Never changed once
// added.

export const SquadId = z.uuid().brand<'SquadId'>();
export type SquadId = z.infer<typeof SquadId>;

export const SquadPlaceId = z.uuid().brand<'SquadPlaceId'>();
export type SquadPlaceId = z.infer<typeof SquadPlaceId>;

/** 吃的, 健身 or 户外: which icon the place wears. */
export const SquadPlaceKind = z
  .enum(['food', 'gym', 'outdoor'])
  .meta({ description: '吃的 (`food`), 健身 (`gym`) or 户外 (`outdoor`).' });
export type SquadPlaceKind = z.infer<typeof SquadPlaceKind>;

/** What a member gives when adding a place. */
export const SquadPlaceFields = {
  name: nameText({
    max: 100,
    description: 'Trimmed, then 1 to 100 characters as people see them, on one line.',
  }),
  kind: SquadPlaceKind,
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
};

/** A place a squad's member added, as kept. */
export interface SquadPlace {
  readonly id: SquadPlaceId;
  readonly squad: SquadId;
  /** Undefined once the adder deleted their account. */
  readonly addedBy: MemberId | undefined;
  readonly name: string;
  readonly kind: SquadPlaceKind;
  readonly latitude: number;
  readonly longitude: number;
  readonly addedAt: Date;
}
