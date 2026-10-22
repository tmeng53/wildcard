import { z } from 'zod';

/**
 * The moves a character can play when it collects an award, as the app names its clips, each
 * with what it looks like for the model. `cheer` is the member's own persona's cheer; the rest
 * are moves every character shares. A move added here must exist in the app first (the
 * character art in ios/Packages/Avatar), or the app falls back to `cheer`.
 */
export const AWARD_MOVES: Readonly<Record<AwardMove, string>> = {
  cheer: '自己性格的庆祝动作（通用，什么奖都合适）',
  pump: '握拳两下，第二下跳起来（拼、狠、坚持）',
  pose: '蹲下再弹起，落地摆 V 字造型定格（高光、名场面）',
  warmup: '左右踢腿热身，张开手臂保持平衡（准备开练、早起）',
  stretch: '伸个大懒腰，打哈欠，晃一晃再抖一抖（早起、慢热）',
  doze: '眼皮打架点头打瞌睡，猛地惊醒假装没事（熬夜、困、休息）',
  flat: '直接躺平，慢慢呼吸，一只脚打拍子（请假、休息日）',
  laugh: '笑到发抖，捂着肚子，差点笑倒（好笑、段子手）',
  wave: '挥手打招呼（打卡准时、在场感）',
  fullbelly: '拍拍吃饱的肚子，开心地晃一晃（好好吃饭，不评价吃了什么）',
};

export const AwardMove = z.enum([
  'cheer',
  'pump',
  'pose',
  'warmup',
  'stretch',
  'doze',
  'flat',
  'laugh',
  'wave',
  'fullbelly',
]);
export type AwardMove = z.infer<typeof AwardMove>;
