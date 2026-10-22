import { Character, Look } from '@wildcard/members';

/** How a member's character looks and moves, wherever the API shows it. */
export const LookBody = Look.meta({
  id: 'Look',
  description:
    'How a member’s character looks and moves, by the ids of the app’s character art. The API ' +
    'keeps no list of them, so new art needs no API change; an app that doesn’t know an id ' +
    'draws that slot’s default.',
});

/** A member's character: the nickname squadmates call them and its look. */
export const CharacterBody = Character.extend({ look: LookBody }).meta({
  id: 'Character',
  description:
    'The member’s character, made in the character editor right after signing in: the ' +
    'nickname squadmates call them and its look. Missing until then.',
});
