-- A coach's lines have a limit per language (Tracy, 2026-11-12): an English line may be about
-- twice as many characters as a Chinese one. The API holds each line to its language's limit;
-- here a column holds the longest of them. The replies, answers, notes, gift lines and letters
-- already hold that much; a challenge's title, unit and line grow to it.

alter table public.coach_member_notes
  drop constraint coach_member_notes_challenge_title_check,
  add constraint coach_member_notes_challenge_title_check
    check (char_length(challenge_title) between 1 and 16),
  drop constraint coach_member_notes_challenge_unit_check,
  add constraint coach_member_notes_challenge_unit_check
    check (char_length(challenge_unit) between 1 and 8),
  drop constraint coach_member_notes_challenge_line_check,
  add constraint coach_member_notes_challenge_line_check
    check (char_length(challenge_line) between 1 and 48);
