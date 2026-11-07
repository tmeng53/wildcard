# Upstream

Vendored unchanged from https://github.com/pbakaus/impeccable (Apache 2.0, `LICENSE` and `NOTICE.md` here), the Claude Code build in its `.claude/skills/impeccable/`: skill 4.8.0, engine 0.1.18, commit `687bc381bc9091bf252c0a05303640561014a425` (2026-11-06). `.agents/skills` links here, so Codex reads the same copy.

Wildcard's part lives outside this folder, so an update never overwrites it: `PRODUCT.md` and `DESIGN.md` at the repo root (read by `scripts/impeccable context` on every run) and `.impeccable/config.json` (`buildPath: code`, no image generation).

Left out on purpose:

- The design detector hook. It scans `.ts`, `.js`, `.html` and `.css` on every edit (the API's TypeScript included) and can't read Swift; `web/` already has ESLint, Prettier and Playwright. Run `scripts/impeccable detect web/public` by hand when changing the site.
- The four `.claude/agents/impeccable-*` subagents: they serve the comp-first build and live mode, which Wildcard doesn't use.

To update: clone the repo at a release, replace this folder's `SKILL.md`, `reference/` and `scripts/` with its `.claude/skills/impeccable/`, keep `LICENSE`, `NOTICE.md` and this file, run `scripts/impeccable doctor` from the repo root and fix what it reports in `PRODUCT.md` or `DESIGN.md`.

The launcher downloads the engine binary from the upstream GitHub release on first run and checks it against `scripts/engine-checksums.txt`; it runs unsandboxed with the session's environment.
