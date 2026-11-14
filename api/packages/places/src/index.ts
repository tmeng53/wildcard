// @wildcard/places: the places a squad's members add themselves.

export {
  createPostgresSquadPlaceStore,
  type SquadPlaceTables,
} from './adapters/postgres-squad-place-store.js';
export { MemberId, PlaceKey } from './domain/ids.js';
export {
  SquadId,
  SquadPlaceFields,
  SquadPlaceId,
  SquadPlaceKind,
  type SquadPlace,
} from './domain/squad-place.js';
export { SquadNotJoinedError, SquadPlaceIdConflictError } from './errors.js';
export type { Clock, SquadMembership, SquadPlaceStore } from './ports.js';
export { createSquadPlaces, type SquadPlaces } from './use-cases/squad-places.js';
