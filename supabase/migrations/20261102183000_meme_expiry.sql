-- A meme can expire (Tracy, 2026-11-02): one tied to a moment, like the clocks going back, gets
-- the day it stops being used; one people keep saying gets none and stays in use until it is
-- turned off. The fixed 4 weeks after approval is gone, so every meme already here has none.
alter table public.memes
  add column expires_at timestamptz,
  add constraint memes_expires_after_approval check (expires_at > approved_at);
