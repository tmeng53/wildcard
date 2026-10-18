---
name: module-structure
description: Where TypeScript code goes in a monorepo. Package kinds, how to structure a module with ports and adapters, reuse before you add, data ownership, and which packages may import which. Use before creating a package or app, when adding a helper, type or adapter, when deciding where new code belongs, and when reviewing imports between packages.
---

# Module structure

Split code by **business capability**, not by technical layer (`services/`, `models/`) and not by user journey. Every package is one of these kinds:

| Kind | What it is |
| --- | --- |
| **Contract** | What modules agree on to work together: shared entities, events, handoff interfaces. Keep it small. |
| **Module** | One capability: its rules and its data. |
| **Flow** | A journey across modules. |
| **Adapter** | Talks to the outside world when the integration is heavy enough to need its own package. Light adapters live inside the package whose port they implement. |
| **App** | A way in: web, API, MCP server, workers. Thin. |
| **Supporting** | No business logic: one technical topic (`errors`, `postgres`, `file-storage`), UI kit, test helpers. Any kind may import it. |

Each package declares its kind in `package.json` (`"<project>": { "kind": "module" }`) so the boundary check can enforce the import rules below.

## Reuse before you add

Every time you are about to add a helper, type, error class, constant or adapter, answer three questions in order. Write the answer in the PR when it isn't obvious.

1. **Does it already exist?** Search before writing: `rg` for the logic itself (not just a name you'd pick), its constants (`'23505'`, `'ENOENT'`, `createHash`), and the shared packages table. If it exists, import it. If a near-copy exists in a module, move it to its shared home and point both callers at it, in the same PR.
2. **Should it be shared?** Shared when a second package needs it now, or when it is plumbing with no business meaning (a database error code, hashing bytes, signing links). Not shared when only one module uses it, or when it carries one module's business rules: that stays in the module, even if it looks generic.
3. **Where is its home?** An existing package named after what the code is about: an error helper goes with errors, a Postgres helper in the `postgres` package. If none fits and it really is shared, create a small supporting package named after that one topic and add it to the table. Never a `utils`, `shared`, `common` or `helpers` package, and never the contract unless every module must agree on it.

A helper with no obvious named home usually belongs where it is used. Also scan the code you touch for copies of what you're adding; removing one is part of the change.

Each project keeps a **shared packages table** in this skill (package, kind, what to reuse it for). A PR that adds a supporting package or a shared export adds or updates its row.

| Package | Kind | Reuse it for |
| --- | --- | --- |
| `@<scope>/errors` | supporting | The base error, the status list, the HTTP mapping, RFC 9457 bodies. See the `errors` skill. |

## One package per topic, adapters inside

A topic is one package, with its port and every adapter for it inside: `file-storage/src/ports.ts` plus `src/adapters/local-folder.ts`, later `gcs.ts` and `s3.ts`. Don't split `file-storage-local` from `file-storage`: callers import one package, and the adapters stay next to the interface they implement. Move an adapter to its own package only when its dependencies are heavy enough that other users of the topic shouldn't install them.

## Wiring: the app is the composition root

- A package declares what it needs as interfaces in `src/ports.ts` (stores, clocks, IDs, signers, clients).
- It exposes plain factory functions that take those ports: `createSellers({ store, clock })`. No container, no decorators, no globals.
- The app picks the adapters at startup from configuration and passes them in. It is the only place that knows which adapter runs.
- Tests wire the same factories with real adapters (a throwaway database) or deterministic ones (a fixed clock).

## Where files go

Use these homes from the first implemented operation. Create only files needed by existing behavior; do not scaffold future actions.

| Code | Home | Responsibility |
| --- | --- | --- |
| Pure business decisions | `src/domain/` | Rules and calculations; no storage, clock reads, randomness or external clients. Pass observations in as values. |
| One business operation | `src/use-cases/<capability>/<verb>-<noun>.ts` | Coordinate ports and domain rules for one action. |
| Capability API factory | `src/use-cases/<capability>.ts` | Types and wiring only. No validation, queries or business decisions. |
| Required dependencies | `src/ports.ts` | Interfaces the package needs. |
| I/O implementations | `src/adapters/` | Queries, generated database types, implementations of ports. |
| Errors | `src/errors.ts` | The package's named errors. See the `errors` skill. |
| Schema changes | `src/migrations/` | Ordered, frozen migrations owned by the package. |
| Cross-module coordination | Flow package, or app `src/flows/` | Journeys involving several modules; handlers delegate here. |
| Transport and startup | App `src/` | Parse requests, format responses, wire adapters, start servers. |
| Developer commands | `scripts/` | Code generation and maintenance, not runtime behavior. |

- Kebab-case filenames, named after the operation. No `service`, `manager`, `helpers` or `utils` files.
- Each action takes only the dependencies it uses.
- `src/index.ts` explicitly exports the public API and contains no implementation. Internal folders have no re-export barrels.
- Tests sit beside the code. Storage tests run on the real database, never an in-memory substitute.

## What becomes a module

Make a new module when the code has its own data (tables only it writes) or its own rules (decisions that change for their own reasons). Otherwise add it to an existing module. Start coarse and split when two parts change for different reasons. Who builds it never affects where it goes.

## Data ownership

When modules share one database:

- A schema and a database role per module; a role reads and writes only its own schema.
- References across modules are ID columns with no foreign key. The flow that creates a reference checks it first through the owner's public API.
- Copy what you need when you write instead of joining later.
- Records other modules point at are never deleted; immutable ones never change.
- Mirror domain rules as database constraints and map violations to the module's errors. Code is the first check; the database is the backstop.
- Migrations are frozen once merged. Table types are generated, not hand-written, and CI checks they are current.

## Who may import what

```
apps ──► flows ──► modules ──► contract
  └────► adapters ──► (the module whose port they implement)
supporting ◄── any kind
```

- Modules never import other modules. Anything that spans modules goes in a flow, or reacts to a contract event.
- Apps hold no business logic.
- No `../` across packages, no deep imports past a package's entry point, no import cycles.

## Enforced

A dependency-cruiser config keyed on each package's declared kind checks these import rules in CI (`pnpm boundaries`): copy this skill's `templates/.dependency-cruiser.js`. The "no utils package" and "one action per file" rules are review-only so far.

Sources: [Turborepo: structuring a repository](https://turborepo.dev/docs/crafting-your-repository/structuring-a-repository) · [Nx: module boundaries](https://nx.dev/blog/mastering-the-project-boundaries-in-nx) · [Medusa: module isolation](https://docs.medusajs.com/learn/fundamentals/modules/isolation) · Ports and adapters (hexagonal architecture)
