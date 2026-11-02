-- Each check-in photo's size in pixels, as the app prepared it, so the feed lays a photo out
-- at its own shape (portrait too) before it loads. Photos saved before sizes were sent have
-- none, and the app shows them in the old landscape box.
alter table public.check_in_photos
  add column width integer check (width between 1 and 10000),
  add column height integer check (height between 1 and 10000),
  add constraint check_in_photos_size_whole check ((width is null) = (height is null));
