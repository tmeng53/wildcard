#!/usr/bin/env bash
# SessionStart hook: give a cloud agent session the same services a laptop and CI have.
# Template from sponge-ai-lab/engineering-skills (cloud-test-environment skill).
# Does nothing on a laptop, where Docker Desktop already runs.
set -euo pipefail
# Steps log to /tmp; on failure, show the log of the step that failed.
log=/tmp/cloud-session-start.log; : >"$log"
trap 'echo "Cloud dev stack failed; last lines of $log:" >&2; tail -20 "$log" >&2' ERR
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "$CLAUDE_PROJECT_DIR"

# 1. Docker: installed in the cloud image but not running.
if ! docker info >/dev/null 2>&1; then
  nohup dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 0.5; done
fi

# 2. Dependencies. Swap in the project's package manager.
pnpm install --frozen-lockfile --prefer-offline >>"$log" 2>&1

# 3. Services from docker-compose.yml, healthy before we return.
if [ ! -f .env ] && [ -f .env.example ]; then cp .env.example .env; fi
docker compose up -d --wait --wait-timeout 120 >>"$log" 2>&1

echo "Cloud dev stack ready: $(docker compose ps --services | tr '\n' ' ')"
