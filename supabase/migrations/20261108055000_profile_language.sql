-- The language the member's app speaks (简体中文, 繁體中文 or English), so the AI writes what
-- they read in it even when it writes without a request of theirs (the coach's wakes, the weekly
-- awards). The API keeps it from the `Accept-Language` the app sends on every call; Simplified
-- Chinese, the app's own default, until it sees another. Like the rest of the profile, the API
-- owns the rule on its values.
alter table public.profiles add column language text not null default 'zh-Hans';

-- The log keeps it with the rest of the profile; rows from before it were all Simplified.
alter table public.profile_events add column language text not null default 'zh-Hans';
