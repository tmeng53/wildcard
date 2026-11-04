-- Every move the app's character art has becomes one the weekly awards may pick: the 动态
-- reaction moves, the head bump and the poke, and each sport kit's move (played holding that
-- sport's prop). The model picks from the moves `weekly_award_settings.moves` describes, so this
-- adds their descriptions, keeps any description already there, and logs the new value.
with changed as (
  update public.weekly_award_settings
  set moves = $moves${
    "bump": "往前探身撞个头庆祝，再弹回来（默契、一起练、搭子）",
    "poked": "像被戳了一下吓一跳，再左右张望（被点名、意外收获）",
    "heart": "胸口蹦出一颗大爱心（暖心、给队友点赞多、人缘好）",
    "flex": "秀肌肉：双手举起展示二头肌，鼓三下（力量、练得狠）",
    "chin-up": "叉腰抬下巴，得意一笑，冒个闪光（得意、嘚瑟、高光时刻）",
    "laugh-bend": "笑弯了腰，眼泪飙出来（段子手、请假条写得好笑）",
    "drool": "星星眼流口水再擦一擦（吃得香、馋了、好好吃饭）",
    "shocked": "头顶冒红色感叹号，吓一跳（反差大、出人意料、突然爆发）",
    "pout": "皱眉跺脚两下冒热气，气鼓鼓（不服输、倔、跟自己较劲）",
    "swim": "戴上泳镜游一段蛙泳（这周游了泳的人）",
    "run": "拿着水杯原地慢跑（这周跑了步、走了路或做了有氧的人）",
    "strength": "举起哑铃推两下再秀肌肉（这周练了力量或格斗的人）",
    "tennis": "抛球发球挥拍（这周打了网球的人）",
    "climb": "手伸进粉袋蘸粉再拍拍手（这周攀了岩的人）",
    "yoga": "铺开瑜伽垫，做树式站稳（这周练了瑜伽或身心类运动的人）",
    "kettlebell": "抱着壶铃做高脚杯深蹲（这周练了壶铃的人）",
    "badminton": "起跳扣杀（这周打了羽毛球的人）",
    "pickleball": "轻轻放个小球过网（这周打了匹克球的人）",
    "pingpong": "发球后握拳庆祝（这周打了乒乓球的人）"
  }$moves$::jsonb || moves
  where not (moves ?& array[
    'bump', 'poked', 'heart', 'flex', 'chin-up', 'laugh-bend', 'drool', 'shocked', 'pout', 'swim',
    'run', 'strength', 'tennis', 'climb', 'yoga', 'kettlebell', 'badminton', 'pickleball', 'pingpong'
  ])
  returning *
)
insert into public.weekly_award_setting_events (settings)
select jsonb_build_object(
  'version', 1,
  'model', model,
  'instructions', instructions,
  'moves', moves
)
from changed;
