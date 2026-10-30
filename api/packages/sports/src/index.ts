// @wildcard/sports: the sports list every picker shows (categories, names, icons and short
// lists), kept in the database so it changes without an app release.

export { createPostgresSportStore, type SportTables } from './adapters/postgres-sport-store.js';
export {
  PICK_LISTS,
  type ListedSport,
  type LocalizedNames,
  type PickList,
  type SportCatalog,
  type SportCategory,
} from './domain/catalog.js';
export {
  CategoryEdit,
  CategoryId,
  LocalizedNamesInput,
  PicksEdit,
  SportEdit,
  SportIcon,
} from './domain/edits.js';
export {
  SportCategoryNotFoundError,
  SportInPickListError,
  SportNotOfferedError,
} from './errors.js';
export type { SportRecord, SportStore } from './ports.js';
export { createSports, type Sports, type SportsAdmin } from './use-cases/sports.js';
