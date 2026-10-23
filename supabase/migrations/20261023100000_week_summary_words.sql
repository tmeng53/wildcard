-- The words of the Sunday summary (周日战报), kept in the database so they change with no app
-- release and no deploy: each award's name, SF Symbol and what a winner won it by, and each
-- count's name, in Chinese and English. One row, owned by the check-ins module (which keeps the
-- awards' and counts' rules), changed only through the admin tools; the API reads it on every
-- request and checks that every award and count it knows has its words.
--
-- Every change is logged with the whole new value, in the same statement as the change, and
-- none for a save that changed nothing, as the AI settings are (settings_log_append_only()).
create table public.week_summary_words (
  only_row boolean primary key default true check (only_row),
  -- {"version": 1, "awards": {kind: {symbol, title, winner}}, "stats": {kind: {...}}}; a
  -- winner's words count with {n}, `one` for 1 and `other` otherwise.
  words jsonb not null check (coalesce(jsonb_typeof(words -> 'version') = 'number', false))
);

create table public.week_summary_word_events (
  id bigint generated always as identity primary key,
  changed_by uuid references auth.users (id) on delete set null,
  at timestamptz not null default now(),
  words jsonb not null check (coalesce(jsonb_typeof(words -> 'version') = 'number', false))
);

create trigger week_summary_word_events_append_only
  before update or delete on public.week_summary_word_events
  for each row execute function public.settings_log_append_only();

create trigger week_summary_word_events_no_truncate
  before truncate on public.week_summary_word_events
  for each statement execute function public.settings_log_append_only();

create trigger week_summary_words_kept
  before delete on public.week_summary_words
  for each row execute function public.settings_row_kept();

create trigger week_summary_words_no_truncate
  before truncate on public.week_summary_words
  for each statement execute function public.settings_row_kept();

-- No grants (the default privileges in the first migration see to that) and no policies.
alter table public.week_summary_words enable row level security;
alter table public.week_summary_word_events enable row level security;

-- The first words: those the API had in code until now.
with first as (
  insert into public.week_summary_words (words) values ($words$
{
  "version": 1,
  "awards": {
    "planCompleted": {
      "symbol": "checkmark.seal.fill",
      "title": { "zh-Hans": "领奖台", "en": "Podium" },
      "winner": {
        "zh-Hans": { "one": "练了 {n} 天", "other": "练了 {n} 天" },
        "en": { "one": "Trained {n} day", "other": "Trained {n} days" }
      }
    },
    "crown": {
      "symbol": "crown.fill",
      "title": { "zh-Hans": "皇冠", "en": "Crown" },
      "winner": {
        "zh-Hans": { "one": "练了 {n} 天", "other": "练了 {n} 天" },
        "en": { "one": "Trained {n} day", "other": "Trained {n} days" }
      }
    },
    "bestDisclaimer": {
      "symbol": "text.bubble.fill",
      "title": { "zh-Hans": "本周最佳请假条", "en": "Day-off note of the week" },
      "winner": {
        "zh-Hans": { "one": "{n} 个回应", "other": "{n} 个回应" },
        "en": { "one": "{n} reaction", "other": "{n} reactions" }
      }
    }
  },
  "stats": {
    "trainedDays": { "zh-Hans": "训练天数", "en": "Days trained" },
    "plannedDays": { "zh-Hans": "计划天数", "en": "Days planned" },
    "checkIns": { "zh-Hans": "打卡", "en": "Check-ins" },
    "disclaimers": { "zh-Hans": "请假条", "en": "Day-off notes" },
    "healthyMeals": { "zh-Hans": "健康餐", "en": "Clean meals" },
    "cheatMeals": { "zh-Hans": "放纵餐", "en": "Cheat meals" },
    "reactionsReceived": { "zh-Hans": "收到的回应", "en": "Reactions received" }
  }
}
$words$::jsonb)
  returning words
)
insert into public.week_summary_word_events (words) select words from first;
