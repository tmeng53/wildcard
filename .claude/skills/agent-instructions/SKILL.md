---
name: agent-instructions
description: How to write and maintain agent instruction files so agents and reviewers follow them - a repo's AGENTS.md and the CLAUDE.md that imports it, and the project instructions set in an assistant's project settings. Use when creating or editing any of these, adding a rule for agents, or setting up review rules for an automated reviewer.
---

# Agent instructions

Agents read instruction files at the start of every session, so every line costs attention on every task. They only work while they are short and true: long files get skimmed, and a wrong rule spreads to every change. Two kinds:

| File | Holds | Read by |
| --- | --- | --- |
| `AGENTS.md` in the repo (with `CLAUDE.md` importing it) | How the code is built: commands, conventions, skills, review rules | Every coding agent and automated reviewer working in the repo |
| Project instructions (an assistant project's settings) | What the project is for and how the assistant works with the people on it | Every conversation and thread in that project |

Code rules live in `AGENTS.md`; project instructions point to it and never repeat it.

## Keep it short and concrete

- **Under about 200 lines.** For every line ask: would removing it cause a mistake? If not, cut it.
- **Accurate beats complete.** A short, true file is worth more than a long one full of vague rules. Every rule is true of the code on `main` or was decided by the owner.
- **Capture the intent, not the wording.** When feedback becomes a rule, write the general principle behind it, not the speaker's phrasing or the one case that prompted it. Prefer a short principle the agent applies with judgment to a detailed procedure; add steps only when a mistake shows they are needed.
- **Concrete over aspirational.** "Run `pnpm test` before you push" helps; "write high-quality code" doesn't.
- `CLAUDE.md` holds one line, `@AGENTS.md`, so every agent reads the same file.

## What goes in it

`AGENTS.md` holds the facts an agent needs in every session. In this order (the root `AGENTS.md` of `sponge-ai-lab/engineering-skills` is this outline as a template):

1. **What the project is**, in two or three lines, and where its plan lives.
2. **Commands**: install, test, lint, end-to-end. Exact commands, not descriptions.
3. **Skills table**: "before you X, read skill Y". Multi-step procedures and area-specific rules live in skills, whose bodies load only when used; the file links them and never copies them.
4. **Architecture**: the parts and how they talk, in a few lines.
5. **Domain rules** a reader can't infer from the code.
6. **Language practices**, only what the linter doesn't enforce.
7. **Testing and verification**: what "done" means and what to run before pushing.
8. **Pull requests**: how to open them and the "never" rules.
9. **`## Code Review Rules`** (below).
10. **Keeping this file current** (below).

Leave out:

- **Anything a linter, hook or CI check already enforces.** Name the check once ("ESLint bans `as` casts"); don't explain the rule again. Never send an agent to do a linter's job. A rule that must always hold belongs in a check, not prose.
- What the code already shows: file-by-file tours, standard conventions of the language, "write clean code".
- Temporary state (this week's milestone, who is working on what). That belongs in the tracker or in agent memory.
- Long procedures. If a rule needs more than a few lines, move it into a skill and link it.

## Nested files

Agents and reviewers use the `AGENTS.md` closest to the file they are changing; Codex concatenates them from the root down. Claude Code loads a subdirectory's `CLAUDE.md` when it works there, so give each nested `AGENTS.md` a `CLAUDE.md` with `@AGENTS.md` too. Add a nested file only when a package has rules that apply only there.

Imports (`@path`) don't save context: an imported file costs the same as inline text. Codex stops reading past 32 KiB of combined instructions.

## Code Review Rules

In `AGENTS.md`, automated reviewers (Codex reads this section by name) apply a `## Code Review Rules` section on top of the rest of the file. Write it as a list of concrete things to flag in this repo:

- Open with the bar: flag only real problems (bugs, broken rules, missing evidence). Formatting, import order and anything a check already catches are not findings.
- Each line names something a reviewer can see in a diff: "an import of another package's internals", "a test that can't fail", "a thrown plain `Error` for something the caller can fix".
- Keep it to the rules this repo actually cares about; it is not a general style guide.

How reviewers find their instructions differs:

| Reviewer | Reads |
| --- | --- |
| Codex | `## Code Review Rules` in the `AGENTS.md` closest to each changed file; posts only high-priority findings |
| Claude Code Review | `CLAUDE.md` files, plus an optional `REVIEW.md`, from the base branch |
| Copilot code review | Its instructions files from the PR's head branch |

## Keeping this file current

End the file with this rule, and follow it:

> This file is code: change it in a PR, and only with rules that are true of the code or decided by the owner. Keep it under 200 lines; move a rule that needs more than a few lines into a skill and link it. When code and this file disagree, fix whichever is wrong in the same PR.

- Add a rule when the same mistake or review comment happens twice, not before.
- Prune in the same PR that makes a rule stale.
- Better still, turn a repeated rule into a type, lint rule or CI check, then shorten the line to name the check.
- Test a change by watching whether agent behavior shifts in the next sessions and reviews.

## Project instructions

- **Durable rules only.** Purpose, how to work with the owner, where things live. Temporary state (a milestone, the current PR stack, who is working on what) goes in agent memory or the tracker. If something temporary must be there, give it a removal date in its heading: `## Current milestone (remove after Oct 23)`.
- **Start with purpose.** A few lines on what the project is and the outcome it is after, so the assistant can judge cases no rule covers.
- **Point, don't copy.** Link the repo's `AGENTS.md` and the plan; say "this file does not repeat it".
- **Write rules as instructions with their reason**, short enough to scan: "Don't build from a shared plan without an explicit ask: acknowledge it and ask what to do."
- **Grow from mistakes.** Add a rule when the assistant gets something wrong twice, and prune lines that are stale or contradict each other every time you edit the file.

## Enforced

No check yet. In review, check line count (`wc -l AGENTS.md`), that every linked path exists, and that no rule restates a lint rule.

Sources: [Claude Code memory](https://code.claude.com/docs/en/memory) · [ChatGPT best practices](https://learn.chatgpt.com/guides/best-practices) · [Writing good agents](https://www.philschmid.de/writing-good-agents) · [Claude Code best practices](https://code.claude.com/docs/en/best-practices) · [Codex best practices](https://developers.openai.com/codex/learn/best-practices) · [Codex on GitHub](https://developers.openai.com/codex/integrations/github) · [Claude Code skills](https://code.claude.com/docs/en/skills) · [Claude Code Review](https://code.claude.com/docs/en/code-review-customize) · [agents.md](https://agents.md/) · [Writing a good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
