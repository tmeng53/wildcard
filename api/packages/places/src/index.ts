// @wildcard/places: how members score the places they train at, one score each, the latest
// standing, and its log; and the places a squad's members add themselves.

export {
  createPostgresPlaceRatingStore,
  type PlaceRatingTables,
} from './adapters/postgres-place-rating-store.js';
export {
  createPostgresSquadPlaceStore,
  type SquadPlaceTables,
} from './adapters/postgres-squad-place-store.js';
export {
  MemberId,
  PlaceKey,
  Stars,
  appleKey,
  squadKey,
  type PlaceRating,
} from './domain/place-rating.js';
export {
  SquadId,
  SquadPlaceFields,
  SquadPlaceId,
  SquadPlaceKind,
  type SquadPlace,
} from './domain/squad-place.js';
export { SquadNotJoinedError, SquadPlaceIdConflictError } from './errors.js';
export type { Clock, PlaceRatingStore, SquadMembership, SquadPlaceStore } from './ports.js';
export { createPlaceRatings, type PlaceRatings } from './use-cases/place-ratings.js';
export { createSquadPlaces, type SquadPlaces } from './use-cases/squad-places.js';
