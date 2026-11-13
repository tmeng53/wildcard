-- An admin's demo accounts (Tracy, 2026-11-13): accounts an admin makes for promo pictures and
-- trying the app, each a member of its own like any other, which the admin switches to from
-- 设置 › 管理员 in the app. Kept apart from the admin's own account, so what is posted there never
-- reaches the admin's own squad, streaks, unlocks or AI budget. One row per account, never
-- changed, so the table is its own log; deleting the account (or the admin's) removes it.
create table public.admin_demo_accounts (
  member_id uuid primary key references auth.users (id) on delete cascade,
  admin_id uuid not null references auth.users (id) on delete cascade,
  made_at timestamptz not null default now(),
  check (member_id <> admin_id)
);

create index admin_demo_accounts_admin_id_idx on public.admin_demo_accounts (admin_id, made_at);

create trigger admin_demo_accounts_append_only
  before update or delete on public.admin_demo_accounts
  for each row execute function public.member_log_append_only();

create trigger admin_demo_accounts_no_truncate
  before truncate on public.admin_demo_accounts
  for each statement execute function public.member_log_append_only();

-- The same lock as every table: the app's tokens never reach it.
alter table public.admin_demo_accounts enable row level security;
revoke all on public.admin_demo_accounts from anon, authenticated;
