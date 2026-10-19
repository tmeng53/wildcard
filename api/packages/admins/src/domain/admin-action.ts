import { z } from 'zod';

/** A member on the admin list: their Supabase Auth user id. */
export const AdminId = z.uuid().brand<'AdminId'>();
export type AdminId = z.infer<typeof AdminId>;

/** An admin tool's name, as MCP clients call it: lower snake case, such as `turn_off_meme`. */
export const ToolName = z
  .string()
  .regex(/^[a-z][a-z0-9_]{0,63}$/)
  .brand<'ToolName'>();
export type ToolName = z.infer<typeof ToolName>;

/**
 * What an admin changed, as stored in `admin_actions.action`: the tool they called and the
 * arguments it was called with.
 */
export const AdminAction = z.strictObject({
  version: z.literal(1),
  tool: ToolName,
  arguments: z.record(z.string(), z.json()),
});
export type AdminAction = z.infer<typeof AdminAction>;

/** One logged change: who made it, when, and what. */
export interface LoggedAdminAction {
  readonly admin: AdminId;
  readonly at: Date;
  readonly action: AdminAction;
}
