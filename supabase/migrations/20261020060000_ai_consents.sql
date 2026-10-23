-- Members' consent to having their words sent to third-party AI (the weekly awards and AI
-- 请假条 drafts), which a member gives once before joining or making a squad. One row per copy
-- version they agreed to, kept as the record of what they were shown and when: a new version
-- of the copy (such as one naming another provider) asks again and adds a row. A consent can't
-- be withdrawn on its own; it goes with the account. As with every table, only our API reads
-- and writes it.

create table public.ai_consents (
  member_id uuid not null references auth.users (id) on delete cascade,
  copy_version int not null check (copy_version > 0),
  given_at timestamptz not null,
  primary key (member_id, copy_version)
);

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.ai_consents enable row level security;
