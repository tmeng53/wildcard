// @wildcard/saved-places: the places each member saved (收藏) with their note, seen only by them,
// and their log.

export {
  createPostgresSavedPlaceStore,
  type SavedPlaceTables,
} from './adapters/postgres-saved-place-store.js';
export {
  MAX_SAVED_PLACES,
  MemberId,
  SavedPlaceNote,
  type SavedPlace,
} from './domain/saved-place.js';
export { PlaceWithoutKeyError, TooManySavedPlacesError } from './errors.js';
export type { Clock, SavedPlaceStore } from './ports.js';
export { createSavedPlaces, type SavedPlaces } from './use-cases/saved-places.js';
