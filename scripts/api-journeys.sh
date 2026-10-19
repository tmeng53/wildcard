#!/usr/bin/env bash
# Drives the API the way the app does, over HTTP, against local Supabase: the built server
# (api/apps/server/dist), real members signed up through Supabase Auth, photos uploaded to
# Supabase Storage. Each step prints one line; any unexpected answer stops the run.
#   scripts/api-journeys.sh [check-in] [photo-upload] [squad] [disclaimer-drafts]   (no arguments: all)
# Needs `supabase start`, pnpm, curl, jq and psql. The verify-wildcard skill's features/ files
# say what each line means and which rows to check.
set -euo pipefail
# Bash 4.4+; macOS ships bash 3.2, where every check still stops the run through `fail`.
shopt -s inherit_errexit 2>/dev/null || true
cd "$(dirname "$0")/.."

journeys="${*:-check-in photo-upload squad disclaimer-drafts}"
for journey in $journeys; do
  case "$journey" in
    check-in | photo-upload | squad | disclaimer-drafts) ;;
    *) echo "api-journeys: unknown journey $journey (check-in, photo-upload, squad, disclaimer-drafts)" >&2 && exit 2 ;;
  esac
done
want() { [[ " $journeys " == *" $1 "* ]]; }

supabase() { if type -P supabase >/dev/null; then command supabase "$@"; else npx --yes supabase@2.121.0 "$@"; fi; }
status="$(supabase status -o env 2>/dev/null)" || {
  echo "api-journeys: local Supabase isn't running (supabase start)" >&2
  exit 1
}
eval "$status"

. scripts/lib/api-server.sh
start_api_server
log="$api_log"
tmp="$(mktemp -d)"
trap 'kill "$server" 2>/dev/null || true; rm -rf "$log" "$tmp"' EXIT
echo "server: $(curl -sf "$api/health")"

fail() {
  echo "FAIL: $*" >&2
  echo "--- server log" >&2
  cat "$log" >&2
  exit 1
}

# call METHOD PATH TOKEN [BODY]: sets $code and $body (the response JSON).
call() {
  local args=(-s -o "$tmp/body" -w '%{http_code}' -X "$1" "$api$2" -H 'content-type: application/json')
  [ -n "$3" ] && args+=(-H "authorization: Bearer $3")
  [ $# -ge 4 ] && args+=(--data "$4")
  code="$(curl "${args[@]}")"
  body="$(cat "$tmp/body")"
}

# expect CODE [REASON]: the last call answered CODE (and, for a problem, this reason).
expect() {
  [ "$code" = "$1" ] || fail "expected $1, got $code: $body"
  if [ $# -ge 2 ]; then
    [ "$(jq -r .reason <<<"$body")" = "$2" ] || fail "expected reason $2: $body"
  fi
}

# A new member signed up through Supabase Auth, as "<user id> <access token>".
sign_up() {
  curl -sf "$API_URL/auth/v1/signup" -H "apikey: $PUBLISHABLE_KEY" -H 'content-type: application/json' \
    --data "{\"email\":\"$(new_id)@example.com\",\"password\":\"$(new_id)\"}" |
    jq -r '"\(.user.id) \(.access_token)"'
}

# A squad the first token creates and the others join by its invite code, as the app does:
# sets $squad and $invite_code.
squad_of() {
  call PUT "/squads/$(new_id)" "$1" '{"version":1,"name":" 早八跑团 "}'
  expect 201
  squad="$(jq -r .id <<<"$body")"
  invite_code="$(jq -r .inviteCode <<<"$body")"
  shift
  for token in "$@"; do
    call POST "/squad-invites/$invite_code/accept" "$token"
    expect 201
  done
}

new_id() { node -p 'crypto.randomUUID()'; }
# A minute ago, in UTC: always inside the API's 48-hour window, and its UTC day.
now="$(node -p 'new Date(Date.now() - 60_000).toISOString()')"
day="${now:0:10}"

read -r me me_token <<<"$(sign_up)"
read -r mate mate_token <<<"$(sign_up)"
read -r outsider outsider_token <<<"$(sign_up)"
for m in "$me" "$mate" "$outsider"; do [[ "$m" =~ ^[0-9a-f-]{36}$ ]] || fail "sign-up failed"; done
squad_of "$me_token" "$mate_token"
echo "members: me=$me mate=$mate outsider=$outsider squad=$squad"

if want check-in; then
  id="$(new_id)"
  trained="{\"version\":1,\"day\":\"$day\",\"createdAt\":\"$now\",\"audience\":[\"$squad\"],\"kind\":\"trained\",\"training\":{\"sport\":\"custom\",\"customSport\":\" 飞盘 \",\"caption\":\"累但爽\"}}"
  call PUT "/check-ins/$id" "$me_token" "$trained"
  expect 201
  [ "$(jq -r .training.customSport <<<"$body")" = "飞盘" ] || fail "custom sport not trimmed: $body"
  echo "check-in: saved trained $id (201)"

  call PUT "/check-ins/$id" "$me_token" "$trained"
  expect 200
  echo "check-in: retry answered with the saved one (200)"

  call PUT "/check-ins/$id" "$me_token" "${trained/累但爽/改了}"
  expect 409 CHECK_IN_ID_CONFLICT
  echo "check-in: different contents under the same id refused (409 CHECK_IN_ID_CONFLICT)"

  disclaimer() { echo "{\"version\":1,\"day\":\"$day\",\"createdAt\":\"$now\",\"audience\":[\"$squad\"],\"kind\":\"disclaimer\",\"disclaimer\":{\"text\":\"$1\"}}"; }
  first="$(new_id)"
  call PUT "/check-ins/$first" "$mate_token" "$(disclaimer 腿还在酸)"
  expect 201
  echo "check-in: mate posted today's disclaimer $first (201)"
  call PUT "/check-ins/$(new_id)" "$mate_token" "$(disclaimer 再来一条)"
  expect 409 DISCLAIMER_ALREADY_POSTED
  echo "check-in: a second disclaimer today refused (409 DISCLAIMER_ALREADY_POSTED)"

  call PUT "/check-ins/$(new_id)" "$outsider_token" "$trained"
  expect 403 SQUAD_NOT_JOINED
  echo "check-in: outsider posting to the squad refused (403 SQUAD_NOT_JOINED)"

  call GET "/squads/$squad/check-ins?from=$day&to=$day" "$mate_token"
  expect 200
  [ "$(jq -c '[.checkIns[].id] | sort' <<<"$body")" = "$(jq -cn --arg a "$id" --arg b "$first" '[$a,$b] | sort')" ] ||
    fail "squad list should hold exactly $id and $first: $body"
  echo "check-in: mate sees both in the squad list ($(jq '.checkIns | length' <<<"$body") check-ins)"

  call GET "/squads/$squad/check-ins?from=$day&to=$day" "$outsider_token"
  expect 403 SQUAD_NOT_JOINED
  echo "check-in: outsider reading the squad refused (403 SQUAD_NOT_JOINED)"

  call GET "/squads/$squad/check-ins?from=$day&to=$day" ""
  expect 401
  echo "check-in: signed-out read refused (401)"

  call GET "/me/check-ins?from=$day&to=$day" "$me_token"
  expect 200
  [ "$(jq -r '[.checkIns[].id] | join(",")' <<<"$body")" = "$id" ] || fail "my list should hold only $id: $body"
  echo "check-in: my list holds only my own ($id)"
fi

if want photo-upload; then
  call POST /photo-uploads "$me_token"
  expect 201
  path="$(jq -r .path <<<"$body")"
  upload_url="$(jq -r .uploadUrl <<<"$body")"
  [[ "$path" == "$me/"* ]] || fail "upload path isn't in my folder: $path"
  echo "photo-upload: got an upload URL for $path (201)"

  head -c 2048 /dev/urandom >"$tmp/photo.jpg"
  uploaded="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$upload_url" -H 'content-type: image/jpeg' --data-binary "@$tmp/photo.jpg")"
  [ "$uploaded" = 200 ] || fail "upload answered $uploaded"
  echo "photo-upload: uploaded 2048 bytes (200)"

  again="$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$upload_url" -H 'content-type: image/jpeg' --data-binary "@$tmp/photo.jpg")"
  [ "$again" != 200 ] || fail "the upload URL worked twice"
  echo "photo-upload: the same upload URL refused a second upload ($again)"

  id="$(new_id)"
  meal="{\"version\":1,\"day\":\"$day\",\"createdAt\":\"$now\",\"audience\":[\"$squad\"],\"kind\":\"healthyMeal\",\"meal\":{\"caption\":\"沙拉\",\"photos\":[{\"path\":\"$path\"}]}}"
  call PUT "/check-ins/$id" "$me_token" "$meal"
  expect 201
  echo "photo-upload: saved healthyMeal $id with the photo (201)"

  call GET "/squads/$squad/check-ins?from=$day&to=$day" "$mate_token"
  expect 200
  view_url="$(jq -r --arg id "$id" '.checkIns[] | select(.id == $id) | .meal.photos[0].url' <<<"$body")"
  [ -n "$view_url" ] && [ "$view_url" != null ] || fail "mate's list has no photo URL for $id: $body"
  curl -sf "$view_url" -o "$tmp/viewed.jpg" || fail "the view URL didn't serve the photo"
  cmp -s "$tmp/photo.jpg" "$tmp/viewed.jpg" || fail "the photo served differs from the one uploaded"
  echo "photo-upload: mate downloaded the same bytes through the view URL"

  call PUT "/check-ins/$(new_id)" "$mate_token" "$meal"
  expect 403 PHOTO_NOT_YOURS
  echo "photo-upload: mate using my photo refused (403 PHOTO_NOT_YOURS)"

  call PUT "/check-ins/$(new_id)" "$me_token" "$meal"
  expect 409 PHOTO_IN_USE
  echo "photo-upload: the photo on a second check-in refused (409 PHOTO_IN_USE)"

  call POST /photo-uploads "$me_token"
  never="$(jq -r .path <<<"$body")"
  call PUT "/check-ins/$(new_id)" "$me_token" "${meal//$path/$never}"
  expect 400 PHOTO_NOT_UPLOADED
  echo "photo-upload: a photo never uploaded refused (400 PHOTO_NOT_UPLOADED)"
fi

if want squad; then
  call GET /me/squads "$mate_token"
  expect 200
  [ "$(jq -c '[.squads[] | {id, name, members: [.members[].userId]}]' <<<"$body")" = \
    "$(jq -cn --arg s "$squad" --arg a "$me" --arg b "$mate" '[{id: $s, name: "早八跑团", members: [$a, $b]}]')" ] ||
    fail "mate's squads should be exactly $squad, named 早八跑团, with me then mate: $body"
  echo "squad: mate's squads list $squad, name trimmed, me then mate"

  read -r newcomer newcomer_token <<<"$(sign_up)"
  typed="$(tr '[:upper:]' '[:lower:]' <<<"${invite_code:0:4}")-${invite_code:4}"
  call GET "/squad-invites/$typed" "$newcomer_token"
  expect 200
  [ "$(jq -c . <<<"$body")" = '{"version":1,"name":"早八跑团","memberCount":2,"full":false,"joined":false}' ] ||
    fail "preview should show the name and 2 members only: $body"
  echo "squad: newcomer previews $typed: 早八跑团, 2 members"

  call POST "/squad-invites/$typed/accept" "$newcomer_token"
  expect 201
  [ "$(jq -r '.members | map(.userId) | last' <<<"$body")" = "$newcomer" ] || fail "newcomer isn't last: $body"
  call POST "/squad-invites/$invite_code/accept" "$newcomer_token"
  expect 200
  echo "squad: newcomer joined (201), joining again answered 200"

  call GET "/squad-invites/ZZZZZZZZ" "$newcomer_token"
  expect 404 INVITE_CODE_UNKNOWN
  echo "squad: an unknown code refused (404 INVITE_CODE_UNKNOWN)"

  call GET "/squads/$squad" "$outsider_token"
  expect 403 SQUAD_NOT_JOINED
  echo "squad: outsider reading the squad refused (403 SQUAD_NOT_JOINED)"

  call DELETE "/squads/$squad/members/me" "$newcomer_token"
  expect 204
  call GET "/squads/$squad" "$newcomer_token"
  expect 403 SQUAD_NOT_JOINED
  call GET /me/squads "$newcomer_token"
  [ "$(jq '.squads | length' <<<"$body")" = 0 ] || fail "newcomer still lists a squad: $body"
  echo "squad: newcomer left (204) and can't read it any more"
fi

if want disclaimer-drafts; then
  ask() { echo "{\"version\":1,\"reason\":\"$1\",\"style\":\"$2\"}"; }
  call POST /disclaimer-drafts "$me_token" "$(ask 早上没起来 funny)"
  expect 503 DISCLAIMER_WRITER_UNAVAILABLE
  if grep -q '"severity":"ERROR"' "$log"; then fail "drafts being off logged an error"; fi
  echo "disclaimer-drafts: no key, so 503 DISCLAIMER_WRITER_UNAVAILABLE (the app shows its dice), no error logged"

  call POST /disclaimer-drafts "$me_token" "$(ask 我不想活了 funny)"
  expect 200
  [ "$(jq -c . <<<"$body")" = '{"version":1,"kind":"care"}' ] || fail "expected the care line: $body"
  echo "disclaimer-drafts: a self-harm reason gets the care line (200), with or without a key"

  call POST /disclaimer-drafts "$me_token" "$(ask 下雨了 poetic)"
  expect 400 REQUEST_INVALID
  call POST /disclaimer-drafts "" "$(ask 下雨了 funny)"
  expect 401 AUTH_TOKEN_MISSING
  echo "disclaimer-drafts: an unknown style refused (400), a signed-out caller refused (401)"

  used="$(psql "$DB_URL" -tAc "select count(*) from public.disclaimer_draft_requests where member_id = '$me'")"
  [ "$used" = 0 ] || fail "nothing was shown, so no batch should count: $used"
  echo "disclaimer-drafts: no batch counted"
fi

echo "api-journeys: ok ($journeys)"
