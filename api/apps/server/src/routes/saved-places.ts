import { OpenAPIHono, createRoute, z } from '@hono/zod-openapi';
import { Place, PlaceKey } from '@wildcard/place-ids';
import {
  MemberId,
  SavedPlaceNote,
  type SavedPlace as SavedPlaceRecord,
  type SavedPlaces,
} from '@wildcard/saved-places';

import { bodyVersion } from '../body-version.js';
import type { VerifyToken } from '../ports.js';
import { jsonBodyFailures, problem } from '../problem.js';
import { requireCaller, type SignedIn } from '../require-caller.js';

const note = SavedPlaceNote.optional().meta({
  description: 'The member’s note on it, left out when they wrote none.',
});

/** A place the member saved (收藏), as they see it. */
export const SavedPlace = z
  .strictObject({
    key: PlaceKey,
    place: Place,
    note,
    savedAt: z.iso.datetime().meta({ description: 'When they saved it, in UTC.' }),
  })
  .openapi('SavedPlace');

export const SavedPlaceList = z
  .strictObject({
    version: bodyVersion(1),
    places: z.array(SavedPlace).meta({ description: 'Newest saved first.' }),
  })
  .openapi('SavedPlaceList');

export const SavedPlaceDraft = z
  .strictObject({
    version: bodyVersion(1),
    place: Place,
    note: SavedPlaceNote.optional().meta({
      description:
        'The note to keep with it; left out, it has none (a note saved before is cleared).',
    }),
  })
  .openapi('SavedPlaceDraft');

export const SavedPlaceSaved = z
  .strictObject({ version: bodyVersion(1), saved: SavedPlace })
  .openapi('SavedPlaceSaved');

function wire(saved: SavedPlaceRecord): z.infer<typeof SavedPlace> {
  return {
    key: saved.key,
    place: saved.place,
    ...(saved.note === undefined ? {} : { note: saved.note }),
    savedAt: saved.savedAt.toISOString(),
  };
}

const signedInFailures = {
  401: problem('No bearer token, or not a valid one'),
  503: problem('Sign-in can’t be checked right now'),
};

/**
 * `GET`, `PUT /me/saved-places` and `DELETE /me/saved-places/{placeKey}`: the places a member
 * saved (收藏) from a place's page, each with an optional note. Only the member sees them.
 */
export function savedPlaces(deps: {
  readonly verifyToken: VerifyToken;
  readonly savedPlaces: SavedPlaces;
}) {
  const list = createRoute({
    method: 'get',
    path: '/me/saved-places',
    operationId: 'listMySavedPlaces',
    summary: 'The places the signed-in member saved (收藏)',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    responses: {
      200: {
        description: 'Their saved places',
        content: { 'application/json': { schema: SavedPlaceList } },
      },
      ...signedInFailures,
    },
  });

  const save = createRoute({
    method: 'put',
    path: '/me/saved-places',
    operationId: 'saveMyPlace',
    summary: 'Save a place (收藏), or change its note',
    description:
      'A place saved already keeps when it was saved and takes the new note. Safe to repeat.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: {
      body: { required: true, content: { 'application/json': { schema: SavedPlaceDraft } } },
    },
    responses: {
      200: {
        description: 'Saved',
        content: { 'application/json': { schema: SavedPlaceSaved } },
      },
      400: problem(
        'Not a valid place or note, or the member keeps the most saved places already ' +
          '(`TOO_MANY_SAVED_PLACES`)',
      ),
      ...jsonBodyFailures,
      ...signedInFailures,
    },
  });

  const remove = createRoute({
    method: 'delete',
    path: '/me/saved-places/{placeKey}',
    operationId: 'removeMySavedPlace',
    summary: 'Remove a saved place',
    description: 'A place not saved answers 204 too, so a retry is safe.',
    security: [{ bearer: [] }],
    middleware: [requireCaller(deps.verifyToken)] as const,
    request: { params: z.strictObject({ placeKey: PlaceKey }) },
    responses: {
      204: { description: 'Removed, or not saved' },
      400: problem('Not a place key'),
      ...signedInFailures,
    },
  });

  return new OpenAPIHono<SignedIn>()
    .openapi(list, async (c) => {
      const places = await deps.savedPlaces.list(MemberId.parse(c.var.caller.userId));
      return c.json({ version: 1 as const, places: places.map(wire) }, 200);
    })
    .openapi(save, async (c) => {
      const { place, note } = c.req.valid('json');
      const saved = await deps.savedPlaces.save({
        member: MemberId.parse(c.var.caller.userId),
        place,
        note,
      });
      return c.json({ version: 1 as const, saved: wire(saved) }, 200);
    })
    .openapi(remove, async (c) => {
      await deps.savedPlaces.remove({
        member: MemberId.parse(c.var.caller.userId),
        key: c.req.valid('param').placeKey,
      });
      return c.body(null, 204);
    });
}
