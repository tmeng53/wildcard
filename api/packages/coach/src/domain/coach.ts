import type { ReaderLanguage } from '@wildcard/language-model';
import { z } from 'zod';

// A coach as the catalog keeps it. Its identity (name, title, catchphrase, its fictional 简历,
// style, look) and its soul (the persona prompt only the model reads) are the coach's own: every squad
// gets the same coach, and what it learns about a squad is that squad's memory, kept apart.
// A coach is never deleted and keeps its id; `offered: false` retires it.

/** A coach's id: lowercase letters, digits and dashes, such as `xiaohun`. Never changes. */
export const CoachId = z
  .string()
  .regex(/^[a-z][a-z0-9-]{1,39}$/)
  .brand<'CoachId'>();
export type CoachId = z.infer<typeof CoachId>;

/** 入门, 进阶 or 专业: a style a squad picks, never a better coach. */
export const CoachTier = z.enum(['entry', 'advanced', 'pro']);
export type CoachTier = z.infer<typeof CoachTier>;

/** The character the app draws for the coach, by the art's id. */
export const CoachLook = z.string().regex(/^[a-z][a-z0-9-]{0,39}$/);

/**
 * A coach's words in another language than Simplified Chinese: what the app shows on its card and
 * 简历, and the name it goes by. Limits are looser than Chinese ones, since English runs longer.
 */
export const CoachWords = z.strictObject({
  name: z.string().trim().min(1).max(20).describe('Its name, such as Poki.'),
  title: z.string().trim().min(1).max(24).describe('Its 头衔, such as Couch Coach.'),
  catchphrase: z.string().trim().min(1).max(80).describe('Its 口头禅.'),
  background: z.string().trim().min(1).max(140).describe('Its fictional 履历.'),
  experience: z.string().trim().min(1).max(30).describe('What 执教 says after the years.'),
  style: z.string().trim().min(1).max(200).describe('Its 执教风格.'),
  tags: z.array(z.string().trim().min(1).max(16)).min(1).max(5).describe('Up to 5 tags.'),
  pay: z.string().trim().min(1).max(30).describe('Its 期望待遇.'),
});
export type CoachWords = z.infer<typeof CoachWords>;

/** A coach, whole, as stored, logged and put by an admin. */
export const Coach = z.strictObject({
  version: z.literal(3),
  id: CoachId.describe('Its id, such as `xiaohun`. Never changes.'),
  position: z
    .int()
    .min(1)
    .max(1000)
    .describe('Its place in 教练招聘会, from 1. Coaches sharing a place go by id.'),
  tier: CoachTier.describe('entry (入门), advanced (进阶) or pro (专业).'),
  name: z.string().trim().min(1).max(20).describe('Its name in the app, such as 小混.'),
  catchphrase: z.string().trim().min(1).max(60).describe('Its 口头禅, shown on its card.'),
  title: z.string().trim().min(1).max(10).describe('Its 头衔 next to its name, such as 混混教练.'),
  background: z
    .string()
    .trim()
    .min(1)
    .max(100)
    .describe('Its fictional 履历, one line on its 简历.'),
  yearsCoaching: z
    .int()
    .min(0)
    .max(60)
    .describe('Its fictional years coaching, the number in 执教 on its 简历.'),
  experience: z
    .string()
    .trim()
    .min(1)
    .max(20)
    .describe('What 执教 says after the years, such as 热情满格.'),
  style: z
    .string()
    .trim()
    .min(1)
    .max(200)
    .describe('Its 执教风格 in a few words, shown in the app.'),
  tags: z
    .array(z.string().trim().min(1).max(6))
    .min(1)
    .max(5)
    .describe('Up to 5 short tags on its card in 教练市场, such as 体院应届.'),
  pay: z.string().trim().min(1).max(20).describe('Its 期望待遇, such as 管饭就行.'),
  soul: z
    .string()
    .min(1)
    .max(20_000)
    .describe('Its persona prompt, Chinese. Only the model reads it; the app never gets it.'),
  look: CoachLook.describe('The character the app draws, by the art’s id.'),
  offered: z.boolean().describe('False retires it: squads can no longer hire it.'),
  translations: z
    .strictObject({ 'zh-Hant': CoachWords.optional(), en: CoachWords.optional() })
    .default({})
    .describe(
      'Its words in 繁體中文 (Taiwan wording) and English. A language left out shows the Chinese ones.',
    ),
});
export type Coach = z.infer<typeof Coach>;

/** The coach with its words in `language`, or its Chinese ones where it has none in it. */
export function coachIn(coach: Coach, language: ReaderLanguage): Coach {
  const words = language === 'zh-Hans' ? undefined : coach.translations[language];
  return words === undefined ? coach : { ...coach, ...words };
}

/** A coach as an admin puts it: every field but the version. */
export const CoachEdit = Coach.omit({ version: true });
export type CoachEdit = z.infer<typeof CoachEdit>;
