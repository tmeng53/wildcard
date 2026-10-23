#!/usr/bin/env bash
# Runs the API on http://127.0.0.1:8080 against local Supabase, where a Debug build of the app
# looks for it, so the simulator signs in, signs up and checks in end to end on this Mac.
# Needs `supabase start`. The simulator can't do a real Sign in with Apple without the team's
# signing, so it makes three test members (member1@wildcard.test to member3@…, password
# wildcard-local); launch a Debug build with
# `-local-backend -test-member member1@wildcard.test wildcard-local`. Passes ANTHROPIC_API_KEY
# and OPENAI_API_KEY through when set, for AI writing. Stops with Ctrl-C.
set -euo pipefail
cd "$(dirname "$0")/.."

status="$(if type -P supabase >/dev/null; then supabase status -o env; else npx --yes supabase@2.121.0 status -o env; fi)" || {
  echo "local-backend: local Supabase isn't running (supabase start)" >&2
  exit 1
}
eval "$status"

for n in 1 2 3; do
  answer="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_URL/auth/v1/admin/users" \
    -H "apikey: $SECRET_KEY" -H "Content-Type: application/json" \
    -d "{\"email\":\"member$n@wildcard.test\",\"password\":\"wildcard-local\",\"email_confirm\":true}")"
  case "$answer" in
    200 | 201) echo "made member$n@wildcard.test" ;;
    422) ;; # already there
    *) echo "local-backend: couldn't make member$n@wildcard.test (HTTP $answer)" >&2 && exit 1 ;;
  esac
done

pnpm --dir api install --frozen-lockfile >/dev/null
pnpm --dir api build >/dev/null
echo "API on http://127.0.0.1:8080 (Ctrl-C stops it)"
PORT=8080 PUBLIC_URL=http://127.0.0.1:8080 ADMIN_PASSWORD_SIGN_IN=on \
  JOBS_TOKEN="$(node -p 'crypto.randomBytes(32).toString("hex")')" DATABASE_URL="$DB_URL" SUPABASE_URL="$API_URL" SUPABASE_SECRET_KEY="$SECRET_KEY" \
  exec node api/apps/server/dist/src/main.js
