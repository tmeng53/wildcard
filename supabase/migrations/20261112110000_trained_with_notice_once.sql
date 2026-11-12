-- A teammate's 训练 that names a member as someone it was done with (一起练) tells them once a
-- post, even when its event is delivered twice or the post is edited.
create unique index notices_one_trained_with_each
  on public.notices (member_id, (subject ->> 'checkIn'))
  where kind = 'trainedWith';
