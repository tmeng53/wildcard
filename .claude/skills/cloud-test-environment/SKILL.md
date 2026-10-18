---
name: cloud-test-environment
description: How to give cloud agent sessions (Claude Code on the web, other hosted agents) the same test services as a laptop and CI, so agents run the full suite and end-to-end tests before they push. Use when setting up a new repo for agents, when tests that need a database or other service can't run in a cloud session, or when adding a service the tests depend on.
---

# Cloud test environment

Agents should run the real test suite, database and all, before they push, not find out from CI. Cloud agent containers usually ship Docker but don't start it. Start it in a session-start hook and bring up the repo's own `docker-compose.yml`, and the cloud session, the laptop and CI run the same services from the same file.

```
laptop:        Docker Desktop already running ─┐
cloud session: session-start hook runs dockerd ├─► docker-compose.yml ─► test, e2e
CI:            runner has Docker               ┘    (same pinned images)
```

## Set it up

1. **Put every service the tests need in `docker-compose.yml`** (`templates/docker-compose.yml`): images pinned to a full version (`postgres:16.4`, not `postgres` or `postgres:16`; a digest when you need byte-identical images), ports on `127.0.0.1`, each with a healthcheck so `docker compose up --wait` returns only when they're ready.
2. **Use local stand-ins for external systems.** A standalone node of a blockchain with instant blocks and pre-funded accounts, a storage emulator, a mail catcher. Tests stay fast and deterministic and need no secrets. Keep one check against the real public test network as a nightly or pre-release job, never on every push.
3. **Add the session-start hook**: copy `templates/scripts/cloud-session-start.sh` and `templates/.claude/settings.json`. The hook runs on startup and resume only, not after compaction. The script exits at once outside a cloud session, then starts Docker, installs dependencies and brings the services up healthy.
4. **Configure the cloud environment** in the agent platform's settings:
   - Network: allow the domains of any external test network the nightly check needs; nothing else.
   - Setup script: paste `templates/environment-setup.sh`, which pre-pulls the images into the cached environment so sessions don't hit registry pull limits.
   - No real secrets in environment variables or the setup script: everyone who uses the environment can read them. Use the platform's secret store for the rare real key (a staging bucket).
5. **Add the stop hook** (`templates/scripts/verify-on-stop.sh`, already wired in the settings template): set its command to the repo's own checks. A cloud session then can't end its turn with red checks on its own changes; it is blocked once, so a check it can't fix ends in a report instead of a loop.
6. **Run the same commands in CI**: `docker compose up -d --wait`, then the same test and e2e commands.
7. **Tell agents** in `AGENTS.md`: run the test suite and e2e before every push.

Per-test throwaway databases (Testcontainers) work unchanged once Docker runs.

## Checklist

- [ ] `docker compose up -d --wait` brings every service up healthy on a laptop.
- [ ] In a fresh cloud session, the hook prints "Cloud dev stack ready" and the full test suite passes.
- [ ] CI runs the same compose file and commands.
- [ ] The cloud environment allows only the external test domains it needs and holds no real secrets.
- [ ] The setup script pre-pulls every image in the compose file.
- [ ] `AGENTS.md` says to run tests and e2e before pushing.

## Avoid

- An in-memory or embedded database in place of the real one: it can't enforce roles and constraints, and drifts from production.
- A hosted test database: accounts, secrets, network round trips and state shared between sessions, for nothing the container doesn't already give you.
- Relying on the cloud environment's cache for running services: containers are never cached, which is why the hook starts them every session.

Known limits (Claude Code on the web): hooks don't load in a session that clones several repositories; the setup script is cached only if it finishes in about 5 minutes.

## Enforced

The checklist. CI running the same compose file keeps it honest: a service missing from the file fails CI too.

Sources: [Claude Code cloud environments](https://code.claude.com/docs/en/cloud-environments) · [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) · [Claude Code hooks](https://code.claude.com/docs/en/hooks)
