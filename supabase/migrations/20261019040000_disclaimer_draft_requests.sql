-- Requests for AI 请假条 drafts, so each member asks at most a day's worth (the first
-- batch and 5 换一批). The API counts a member's rows in the last 24 hours before it asks the
-- model, and deletes their older rows as it goes, so the table stays small. As with every
-- table, only our API reads and writes it.

create table public.disclaimer_draft_requests (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references auth.users (id) on delete cascade,
  requested_at timestamptz not null
);

create index disclaimer_draft_requests_member_idx
  on public.disclaimer_draft_requests (member_id, requested_at);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.disclaimer_draft_requests enable row level security;
