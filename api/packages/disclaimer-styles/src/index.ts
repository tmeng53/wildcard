import { z } from 'zod';

// @wildcard/disclaimer-styles: the styles a 请假条 draft is written in. The meme library tags
// each meme with the styles it suits, and the AI drafts read those tags, so both modules agree
// on this one list.

/** The four styles (Tracy, 2026-10-19), as the wire names them: 搞笑, 发疯, 中二, 嘴硬. */
export const DisclaimerStyle = z.enum(['funny', 'unhinged', 'heroic', 'stubborn']);
export type DisclaimerStyle = z.infer<typeof DisclaimerStyle>;
