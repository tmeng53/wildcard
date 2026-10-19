-- Admins, and a log of every change they make through the admin MCP server (the API's
-- /mcp route). Only the API reads and writes these, like every other table.

-- The members who may use the admin tools. Added by hand (SQL), never through the API.
create table public.admins (
  member_id uuid primary key references auth.users (id) on delete cascade,
  added_at timestamptz not null default now()
);

-- One row per change an admin made: who, when, and what, as stored JSON with its shape's
-- version at the top: {"version": 1, "tool": ..., "arguments": {...}}. Kept when the admin
-- leaves the list, and when they delete their account (every member can), with no one named.
create table public.admin_actions (
  id bigint primary key generated always as identity,
  admin_id uuid references auth.users (id) on delete set null,
  at timestamptz not null,
  action jsonb not null check (coalesce(jsonb_typeof(action -> 'version') = 'number', false))
);

create index admin_actions_admin_id_at_idx on public.admin_actions (admin_id, at desc);

-- The same lock as every table: the app's tokens never reach these.
alter table public.admins enable row level security;
alter table public.admin_actions enable row level security;
revoke all on public.admins, public.admin_actions from anon, authenticated;
