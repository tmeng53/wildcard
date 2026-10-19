// @wildcard/memes: the meme library the AI draws on for 今日请假条, its rules and its table.

export { createPostgresMemeStore, type MemeTables } from './adapters/postgres-meme-store.js';
export { MemeDraft, MemeId, MemePhrase, MemeStyle, type MemeRecord } from './domain/meme.js';
export { MemeNotFoundError } from './errors.js';
export type { Clock, MemeStore } from './ports.js';
export { createMemes, type Memes } from './use-cases/memes.js';
