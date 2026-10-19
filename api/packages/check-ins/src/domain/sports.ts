import { z } from 'zod';

/**
 * The listed sports, in the picker's order. This is the list of record: the app's `Sport`
 * (ios/Packages/Contracts) is tested against the OpenAPI document, so a new sport lands here
 * first and the app follows.
 */
export const SPORTS = [
  // 跑走
  'run',
  'walk',
  'hike',
  'trailRun',
  // 力量
  'strength',
  'crossfit',
  'hyrox',
  'kettlebell',
  // 有氧和课程
  'spin',
  'elliptical',
  'rowing',
  'hiit',
  'jumpRope',
  'aerobics',
  // 身心
  'yoga',
  'matPilates',
  'reformerPilates',
  'barre',
  'stretching',
  // 水上
  'swim',
  'surf',
  'paddleboard',
  'kayak',
  // 球拍
  'tennis',
  'badminton',
  'pickleball',
  'tableTennis',
  'squash',
  // 球类
  'basketball',
  'soccer',
  'volleyball',
  'golf',
  'baseballSoftball',
  'ultimate',
  // 骑行
  'roadCycling',
  'mountainBiking',
  // 户外和冬季
  'climb',
  'ski',
  'snowboard',
  'skate',
  // 格斗
  'boxing',
  'kickboxing',
  'jiuJitsu',
  'martialArts',
  // 舞蹈
  'dance',
  // 生活也算练
  'dogWalk',
  'walkCommute',
  'bikeCommute',
  'deepClean',
  'moving',
  'strollerWalk',
  'gardening',
] as const;

/** A 练了's `sport`: a listed sport, or `custom` with the member's own name in `customSport`. */
export const SportKey = z.enum([...SPORTS, 'custom']).meta({
  id: 'Sport',
  description: 'A listed sport, or `custom` with the member’s own name in `customSport`.',
});
export type SportKey = z.infer<typeof SportKey>;
