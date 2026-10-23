-- The AI's words on a squad's Sunday 战报 pages beyond the titles: the order of the middle
-- pages, the podium's 颁奖词 and moves, the 吃了 line, the best 请假条's moves and the ending's
-- headline, line and move. Each member's own lines (你的一周, 你最火的一条) sit with their
-- titles in weekly_award_winners.award. A new column rather than an edit to the awards
-- migration, which the hosted database already ran.

-- Stored JSON with its shape's version at the top: {"version": 1, ...}. The API owns the shape
-- and parses it on every read. Null for awards given before the story had words.
alter table public.weekly_awards
  add column story jsonb check (story is null or coalesce(jsonb_typeof(story -> 'version') = 'number', false));
