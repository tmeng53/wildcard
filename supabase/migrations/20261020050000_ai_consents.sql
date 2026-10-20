-- Members' consent to having their words sent to a third-party AI (the weekly awards and AI
-- 请假条 drafts), which a member gives before joining or making a squad. One row per consent
-- given, kept as the record of what they agreed to: the version of the copy they were shown,
-- the provider it named, and when. Withdrawing stamps the open rows; giving it again adds a row.
-- As with every table, only our API reads and writes it.

create table public.ai_consents (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references auth.users (id) on delete cascade,
  copy_version int not null check (copy_version > 0),
  provider text not null check (provider in ('openai', 'anthropic')),
  given_at timestamptz not null,
  withdrawn_at timestamptz check (withdrawn_at >= given_at)
);

create index ai_consents_member_idx on public.ai_consents (member_id, given_at desc);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.ai_consents enable row level security;
