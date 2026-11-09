-- The first handover letter (2026-11-09) was written under the old prompt, which asked for a note
-- from coach to coach, so it read like a briefing on each member. Tracy asked for it to be
-- rewritten as the farewell to the squad and the next coach that the prompt now asks for. Letters
-- are append-only, so this one change lifts the guard for the update and puts it back.

alter table public.coach_letters disable trigger coach_letters_append_only;

update public.coach_letters
set text = '我被换下来了，这事我早有心理准备，证书到现在也没考。跟大家混了这阵子，你们练得比我认真，放纵餐也发得比我理直气壮，挺好。以后鸭梨娜接手，她比我勤快，大家多担待。鸭梨娜，这队人自觉，不用催，偶尔被他们笑两句就当是夸你。我先溜了，有空回来看你们打卡。'
where id = 1
  and squad_id = '878c06a3-ecc7-4f03-b0a9-773e787298d5'
  and from_coach = 'xiaohun'
  and to_coach = 'yalina';

alter table public.coach_letters enable trigger coach_letters_append_only;
