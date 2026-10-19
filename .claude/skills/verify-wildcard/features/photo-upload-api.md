# Photo on a check-in through the API

**Status: Ready** since photo upload (#23) and photos on check-ins (#27), driven over HTTP by `scripts/api-journeys.sh photo-upload`; CI's `supabase` job runs it. The app's photo picker is in #26 and isn't covered here.

A member asks the API for an upload URL, uploads a photo straight to Storage, saves a 健康餐 with it, and a squad-mate downloads the same bytes through the view URL the squad list hands out. Photos never pass through the API. Stand-ins as in `check-in-api.md`; the photo is 2 KiB of random bytes sent as `image/jpeg`.

Code: `api/apps/server/src/routes/photo-uploads.ts`, `api/apps/server/src/adapters/supabase-storage.ts`, `api/packages/check-ins/src/domain/photos.ts`.

## Drive it

```sh
scripts/api-journeys.sh photo-upload 2>&1 | tee /tmp/verify-wildcard/<short sha>/photo-upload-api.log
```

Same setup as `check-in-api.md`.

## Expected output

Copied from a real run:

```text
server: {"version":1,"status":"ok"}
members: me=<id> mate=<id> outsider=<id> squad=<id>
photo-upload: got an upload URL for <me>/<photo id> (201)
photo-upload: uploaded 2048 bytes (200)
photo-upload: the same upload URL refused a second upload (400)
photo-upload: saved healthyMeal <id> with the photo (201)
photo-upload: mate downloaded the same bytes through the view URL
photo-upload: mate using my photo refused (403 PHOTO_NOT_YOURS)
photo-upload: the photo on a second check-in refused (409 PHOTO_IN_USE)
photo-upload: a photo never uploaded refused (400 PHOTO_NOT_UPLOADED)
api-journeys: ok (photo-upload)
```

## Evidence

- `psql "$DB_URL" -c "select bucket_id, name, metadata->>'size' from storage.objects where name like '<me>/%'"`: one object, 2048 bytes; the path that was never uploaded has none.
- `select * from public.check_in_photos where check_in_id = '<id>'`: the photo's path at position 1, and no other check-in lists it.

## Worth probing

- A fourth photo, or the same photo twice on one check-in (400).
- A path in someone else's folder that does exist (403 `PHOTO_NOT_YOURS`), and a made-up path that doesn't look like `<uuid>/<uuid>` (400).
- A file over 10 MiB or of another type: Storage refuses the upload.
- The view URL stops working after an hour.
