import type { AdminId } from '@wildcard/admins';
import { ToolName } from '@wildcard/admins';
import type { z } from 'zod';

/**
 * One tool of the admin MCP server. It does its work through a module's public functions,
 * never the tables. A tool that `changes` something has each successful call logged with its
 * arguments; one that only reads is not logged.
 */
export interface AdminTool {
  readonly name: ToolName;
  readonly title: string;
  /** What the tool does, for the model choosing a tool. English, like the code. */
  readonly description: string;
  readonly changes: boolean;
  readonly input: z.ZodObject;
  /** Runs one call with input `input` has parsed; answers with JSON. */
  readonly run: (input: Record<string, unknown>, context: AdminToolContext) => Promise<unknown>;
}

/** Who is calling a tool. */
export interface AdminToolContext {
  readonly admin: AdminId;
}

/** Declares a tool with typed input; `run` gets the input its schema parsed. */
export function adminTool<Input extends z.ZodObject>(tool: {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  readonly changes: boolean;
  readonly input: Input;
  readonly run: (input: z.infer<Input>, context: AdminToolContext) => Promise<unknown>;
}): AdminTool {
  return {
    ...tool,
    name: ToolName.parse(tool.name),
    run: (input, context) => tool.run(tool.input.parse(input), context),
  };
}
