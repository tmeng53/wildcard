---
name: zod
description: How to write Zod 4 schemas. Schema-first types, strict objects, discriminated unions, brands, parsing at boundaries, refinements, transforms, and versioned stored JSON. Use before adding or changing a Zod schema, a JSON shape stored in a database JSON column or in file storage, or code that parses untrusted input, and when reviewing any of these.
---

# Zod

Use Zod 4 at every boundary (`zod` in each package's `package.json`). These rules follow [Zod's own documentation](https://zod.dev); when the docs and this file disagree, check the docs for the installed version and fix this file.

## The schema is the source of truth

- Write the schema, derive the type: export both under one name (`export const OrderId = …; export type OrderId = z.infer<typeof OrderId>;`). Never write an interface that mirrors a schema.
- When a schema transforms, its input and output differ: use `z.input<typeof S>` for what callers pass and `z.output<typeof S>` (same as `z.infer`) for what they get back.
- One schema per shape, in the package that owns the shape. A shape that crosses a module boundary lives in the contract package (see `module-structure`).

## Use Zod 4 APIs

The Zod 3 forms below still run, but Zod 4 deprecated or replaced them. Use the right column in new code, and switch a file over when you change it anyway.

| Zod 3 | Zod 4 |
| --- | --- |
| `z.object({…}).strict()` | `z.strictObject({…})` |
| `.passthrough()` | `z.looseObject({…})` |
| `A.merge(B)`, `z.intersection(A, B)` of objects | `z.strictObject({ ...A.shape, ...B.shape })` |
| `z.string().email()`, `.uuid()`, `.url()`, `.datetime()` | `z.email()`, `z.uuid()`, `z.url()`, `z.iso.datetime()` |
| `z.number().int()` | `z.int()` |
| `z.nativeEnum(E)` | `z.enum(E)` |
| `{ message: '…' }`, `errorMap`, `invalid_type_error` | `{ error: '…' }` |
| `err.format()`, `err.flatten()` | `z.treeifyError(err)`, `z.flattenError(err)`, `z.prettifyError(err)` |
| `z.record(V)` | `z.record(K, V)` |
| `.describe('…')` | `.meta({ description: '…' })` (`.describe` is shorthand for it) |

## Objects

- **`z.strictObject` by default.** An unknown key is a bug or an attack, and strict parsing reports it instead of dropping it silently. Use `z.object` (strips unknown keys) only where extra keys are expected and harmless by design, such as environment variables or a third party's payload, and say why in a comment.
- **Compose by spreading shapes**, not `.merge` or `z.intersection`: `z.strictObject({ ...Base.shape, extra: z.string() })`. It is what Zod recommends and the fastest for TypeScript.
- **Bound everything untrusted.** Strings get `.max()`, arrays get `.max()`, integers get `.min()`/`.max()` where a range exists. An unbounded field from an agent is a denial-of-service hole.

## Tagged shapes

- **Model alternatives as a `z.discriminatedUnion`** on a literal tag, not as one object with optional fields (make invalid states unrepresentable). Zod picks the branch by the tag, so it is faster than `z.union` and its error names the expected tags.
- Use `z.union` only when members aren't objects with a shared tag (`z.union([z.literal('complete'), Sampled])`).
- Narrow with an exhaustive `switch` on the tag; the lint rule catches a missing case.

```ts
const Card = z.strictObject({ kind: z.literal('card'), last4: z.string().length(4) });
const Wallet = z.strictObject({ kind: z.literal('wallet'), address: z.string().max(256) });
export const PaymentSource = z.discriminatedUnion('kind', [Card, Wallet]);
export type PaymentSource = z.infer<typeof PaymentSource>;
```

## Strings, numbers and ids

- Use the top-level formats: `z.uuid()` (RFC 9562 UUIDs), `z.iso.datetime()` (ISO 8601, UTC `Z` only unless you pass `{ offset: true }`), `z.url()`, `z.email()`.
- Use `z.int()` for counts and money in minor units, never `z.number()`.
- **Brand values that must not mix:** `z.uuid().brand<'OrderId'>()`. A brand is compile-time only; the only way to get one is to parse, so a branded value has always been checked.

## Parse at the boundary, once

- Parse where data enters: a request, a tool call, a database row, a file, a message from another service, an environment variable. Inside, pass the typed value and don't parse it again.
- **`safeParse` when the caller can act on bad input**, then turn the failure into the package's own error (see `errors`) with `z.prettifyError(result.error)` as its `detail`. **`parse` only where failure is a bug** (data your own code just wrote and typed).
- Never match on Zod's message text. Read `issue.code` and `issue.path` if code must branch on why it failed.
- Use `parseAsync`/`safeParseAsync` only when a schema has async refinements; keep I/O out of schemas where you can.

## Refinements and transforms

- **Refinements never throw** and stay pure: no clock, randomness or I/O, as in domain code. Use `.refine` for one check, `.superRefine` to report several issues with their own paths. Put a cross-field rule on the object that holds both fields.
- **Transforms are one-way.** Keep them at the edge (parse a string into a typed value); don't hide business logic in them. When a value must round-trip (decode on read, encode on write), use a codec (`z.codec`) instead of two hand-written transforms.
- **`.default()` must be a valid output value**; use `.prefault()` when the default should go through parsing. Don't use `.catch()` on untrusted input: it turns bad data into good-looking data.
- **Recursive objects use a getter** (`get children() { return z.array(Node); }`), Zod 4's documented way; `z.lazy` remains for recursive unions such as `JsonValue`.

## Metadata and JSON Schema

- Describe fields an agent sees (MCP tool inputs and outputs) with `.meta({ description })`; `z.toJSONSchema` copies it into the generated schema.
- `z.toJSONSchema` can't represent transforms, dates or bigints, and throws on them by default. Keep agent-facing schemas plain JSON, and pass `io: 'input'` when you publish the input side of a transforming schema.

## Stored JSON carries a version

Every JSON shape you store, in a database JSON column or as a document in file storage, has a top-level `version` field (an integer from 1). A reader can then always tell which shape it holds, long after the code that wrote it has changed.

### The pattern

Each version is its own strict Zod schema with `version: z.literal(n)`. The reader parses a Zod [discriminated union](https://zod.dev/api#discriminated-unions) of every version still stored: Zod picks the branch by that one key and reports an unknown version clearly. Writers write only the latest version.

Old versions are upgraded **one step at a time**, like database migrations: each case of `upgrade` lifts its version by exactly one and hands the result back to `upgrade`, until the latest version returns as is. Adding version 10 is one new schema, one new union member and one new step; earlier steps never change. The `switch` has no `default`, so a version without a step fails to compile, and the exhaustive-switch lint rule (in the `verification` skill's ESLint config) flags it too.

```ts
const NoteV1 = z.strictObject({ version: z.literal(1), text: z.string() });
const NoteV2 = z.strictObject({ version: z.literal(2), lines: z.array(z.string()) });
const NoteV3 = z.strictObject({
  version: z.literal(3),
  lines: z.array(z.string()),
  pinned: z.boolean(),
});
export const Note = NoteV3; // what writers write
export type Note = z.infer<typeof Note>;

const AnyNote = z.discriminatedUnion('version', [NoteV1, NoteV2, NoteV3]);
type AnyNote = z.infer<typeof AnyNote>;

/** One step per version: each case lifts its version by one, then the next step runs. */
function upgrade(note: AnyNote): Note {
  switch (note.version) {
    case 1:
      return upgrade({ version: 2, lines: [note.text] });
    case 2:
      return upgrade({ version: 3, lines: note.lines, pinned: false });
    case 3:
      return note;
  }
}

/** Reads any stored version and returns the latest shape, checked against the latest schema. */
export const StoredNote = AnyNote.transform(upgrade).pipe(Note);
```

A shape with one version is still written this way (`version: z.literal(1)`, a union of one), so adding version 2 later is a new member and a new step, not a guess about unversioned rows.

The `.pipe(Note)` matters: a transform's return value is trusted, not validated, so without it an upgrade could hand back a value that breaks a refinement or `.min()` on the latest schema.

### Retiring an old shape

Old and new code run side by side during a rolling deploy, and other consumers may read the same data. So moving stored data off an old shape, whether bumping a version or giving unversioned JSON its first one, goes in this order:

1. **Readers accept both shapes.** Deploy readers that read the old and the new shape. Writers still write the old one.
2. **Writers switch, and every old writer is drained.** Move writers to the new shape (`Note` points at it). Replace every old instance, and finish or cancel queued jobs that still write the old shape.
3. **Backfill, then check.** Rewrite stored data into the new shape (for unversioned JSON, the backfill writes `version: 1`). Then query to confirm none of the old shape remains.
4. **Drop the old.** Remove the old schema and its upgrade step.

Backfilling before step 2 finishes loses nothing only by luck: a late old writer can add old-shape rows after the backfill ran. Signed and hashed records stop after step 2 (see below).

### Change in place or bump

Before changing a shape, check two things:

1. Does production hold data of the current version?
2. Does any running reader or writer (an old app instance during a rollout, a queued job, a separate consumer) still use it?

If neither, change the shape in place and keep the version: an upgrade step for data that can't exist is dead code. If either, bump the version and retire the old one in the order above. Otherwise old-shape documents would carry the number new readers expect for the new shape.

### Signed and hashed records

Never upgrade a signed or hashed record (a receipt, an audit entry) in place: its signature covers the bytes as written. Verify it in the version it was signed in, so its schema stays as long as such records do.

## Enforced

The `verification` skill's ESLint config bans `as` casts and requires exhaustive switches. The other rules here are review-only: the `## Code Review Rules` in `AGENTS.md` flag unversioned stored JSON and readers that drop a stored version.
