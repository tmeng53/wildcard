-- What only the public beta has (Tracy, 2026-11-09), each on a switch of its own, so once the
-- beta ends each is turned off by itself with `put_switch`, with no app release. The app reads
-- them from `/public/catalog`'s `switches`; one it can't find there is off.
insert into public.switches (id, label, mode) values
  ('betaFreePlan', '公测: 小队设置 订阅 row with 限时免费', 'on'),
  ('betaFeedbackReward', '公测: 意见反馈 line on the mystery reward for feedback', 'on');
