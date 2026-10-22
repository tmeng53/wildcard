# Sourced, not run: starts the built API (api/apps/server/dist) against local Supabase on a free
# port, as Cloud Run starts it (naming itself by that URL, as the admin MCP server's metadata
# needs), with the consent page's password sign-in on (local Supabase has no Apple), without an
# Anthropic key (CI has none, and the drafts journey proves the server runs without one), with a
# fresh JOBS_TOKEN for the scheduler's jobs, and stops it when the calling script exits. Needs the status variables of
# `supabase status -o env` (DB_URL, API_URL, SECRET_KEY) already set.
# Sets $api (its URL), $server (its pid), $api_log (its output) and $jobs_token.
start_api_server() {
  pnpm --dir api install --frozen-lockfile >/dev/null
  pnpm --dir api build >/dev/null
  local port
  port="$(node -e 'const s=require("net").createServer().listen(0,()=>{console.log(s.address().port);s.close()})')"
  api="http://127.0.0.1:$port"
  api_log="$(mktemp)"
  jobs_token="$(node -p 'crypto.randomBytes(32).toString("hex")')"
  env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY PORT="$port" PUBLIC_URL="$api" ADMIN_PASSWORD_SIGN_IN=on JOBS_TOKEN="$jobs_token" DATABASE_URL="$DB_URL" SUPABASE_URL="$API_URL" SUPABASE_SECRET_KEY="$SECRET_KEY" \
    node api/apps/server/dist/src/main.js >"$api_log" 2>&1 &
  server=$!
  trap 'kill "$server" 2>/dev/null || true; rm -f "$api_log"' EXIT
  for _ in $(seq 50); do
    curl -sf "$api/health" >/dev/null && return 0
    kill -0 "$server" 2>/dev/null || { cat "$api_log" >&2; return 1; }
    sleep 0.2
  done
  echo "api-server: no answer from $api/health" >&2
  cat "$api_log" >&2
  return 1
}
