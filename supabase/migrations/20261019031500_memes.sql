-- The meme library: trending memes the AI may weave into a 今日请假条. Claude picks
-- candidates each week; only the ones Tracy approves are saved here. Each is used for a
-- while after its approval, then left out (that rule lives in the API's memes module).
-- As with every table, only our API reads and writes it; the database keeps what must stay
-- true however it is written.

create table public.memes (
  id uuid primary key default gen_random_uuid(),
  -- The meme itself, e.g. 「city不city」. Saved once: approving it again changes nothing.
  phrase text not null unique,
  -- Its background, meaning, the styles it suits and where it trends, as
  -- stored JSON with its shape's version at the top: {"version": 1, ...}. The API owns the
  -- shape and parses it on every read.
  payload jsonb not null check (coalesce(jsonb_typeof(payload -> 'version') = 'number', false)),
  approved_at timestamptz not null,
  -- Set when Tracy turns a meme off; it is never used again.
  disabled_at timestamptz
);

create index memes_approved_at_idx on public.memes (approved_at desc);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.memes enable row level security;
