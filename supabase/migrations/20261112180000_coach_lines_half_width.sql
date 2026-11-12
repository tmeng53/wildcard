-- A coach's lines count an ASCII character (an English letter, digit, space or mark) as half
-- (Tracy, 2026-11-12), so an English line gets as much room as a Chinese one. The API checks the
-- limit as it counts; here each line may hold up to twice its limit in characters.

alter table public.coach_replies
  drop constraint coach_replies_text_check,
  add constraint coach_replies_text_check check (char_length(text) between 1 and 200);

alter table public.coach_answers
  drop constraint coach_answers_text_check,
  add constraint coach_answers_text_check check (char_length(text) between 1 and 200);

alter table public.coach_notes
  drop constraint coach_notes_text_check,
  add constraint coach_notes_text_check check (char_length(text) between 1 and 120);

alter table public.coach_member_notes
  drop constraint coach_member_notes_text_check,
  add constraint coach_member_notes_text_check check (char_length(text) between 1 and 120);

alter table public.grants
  drop constraint grants_line_check,
  add constraint grants_line_check check (char_length(line) between 1 and 120);

alter table public.coach_letters
  drop constraint coach_letters_text_check,
  add constraint coach_letters_text_check check (char_length(text) between 1 and 400);
