#!/usr/bin/env bash
# Drives the API the way the app does, over HTTP, against local Supabase: the built server
# (api/apps/server/dist), real members signed up through Supabase Auth, photos uploaded to
# Supabase Storage. Each step prints one line; any unexpected answer stops the run.
#   scripts/api-journeys.sh [check-in] [photo-upload] [squad] [disclaimer-drafts] [weekly-plan]
#     [squad-today] [week-summary] [reactions] [devices] [account] [admin-mcp]   (no arguments: all)
# Needs `supabase start`, pnpm, node, curl, jq and psql. The verify-wildcard skill's features/ files
# say what each line means and which rows to check.
set -euo pipefail
# Bash 4.4+; macOS ships bash 3.2, where every check still stops the run through `fail`.
shopt -s inherit_errexit 2>/dev/null || true
cd "$(dirname "$0")/.."

journeys="${*:-check-in photo-upload squad disclaimer-drafts weekly-plan squad-today week-summary reactions devices account admin-mcp}"
for journey in $journeys; do
  case "$journey" in
    check-in | photo-upload | squad | disclaimer-drafts | weekly-plan | squad-today | week-summary | reactions | devices | account | admin-mcp) ;;
    *) echo "api-journeys: unknown journey $journey (check-in, photo-upload, squad, disclaimer-drafts, weekly-plan, squad-today, week-summary, reactions, devices, account, admin-mcp)" >&2 && exit 2 ;;
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

# A time zone where it is about noon now, as "<zone> <its today> <its week's Monday>": a member
# there is well inside their day (which lasts until 3am), whenever the run happens.
noon_zone() {
  node -e '
    const offset = ((12 - new Date().getUTCHours() + 36) % 24) - 12;
    const local = new Date(Date.now() + offset * 3_600_000);
    const monday = new Date(local.getTime() - ((local.getUTCDay() + 6) % 7) * 86_400_000);
    const zone = offset === 0 ? "Etc/GMT" : `Etc/GMT${offset > 0 ? "-" : "+"}${Math.abs(offset)}`;
    console.log(zone, local.toISOString().slice(0, 10), monday.toISOString().slice(0, 10));'
}
# days_after DAY N: the date N days after DAY.
days_after() { node -p "new Date(Date.parse('$1') + $2 * 86_400_000).toISOString().slice(0, 10)"; }
# A check-in to a squad on a member's day: check_in_of SQUAD DAY KIND FIELDS.
check_in_of() { echo "{\"version\":1,\"day\":\"$2\",\"createdAt\":\"$now\",\"audience\":[\"$1\"],\"kind\":\"$3\",$4}"; }

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

  # The web invite page, before anyone signs in: no token, only the name, size, whether full
  # and the members' looks (none here: neither has made a character), never names or ids.
  call GET "/public/squad-invites/$typed" ""
  expect 200
  [ "$(jq -c . <<<"$body")" = '{"version":1,"name":"早八跑团","memberCount":2,"full":false,"looks":[]}' ] ||
    fail "public preview should show the name, size, full and looks only: $body"
  call GET "/public/squad-invites/ZZZZZZZZ" ""
  expect 404 INVITE_CODE_UNKNOWN
  echo "squad: anyone previews $typed without signing in; an unknown code answers 404"

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

if want weekly-plan; then
  read -r planner planner_token <<<"$(sign_up)"
  read -r zone today monday <<<"$(noon_zone)"
  next="$(days_after "$monday" 7)"
  call GET "/me/weekly-plans/$next" "$planner_token"
  expect 200
  call PUT "/me/weekly-plans/$next" "$planner_token" '{"version":1,"days":[{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"},{"kind":"rest"}]}'
  expect 400 TIME_ZONE_NOT_SET
  echo "weekly-plan: no profile yet, so saving is refused (400 TIME_ZONE_NOT_SET)"

  call PUT /me/profile "$planner_token" "{\"version\":1,\"timeZone\":\"$zone\"}"
  expect 200
  call GET "/me/weekly-plans/$monday" "$planner_token"
  expect 200
  [ "$(jq -c '[.source, (.days | map(.kind))]' <<<"$body")" = '["default",["train","train","rest","train","train","train","rest"]]' ] ||
    fail "this week should be the default, rest on Wednesday and Sunday: $body"
  echo "weekly-plan: this week ($monday, $zone) is the default, rest on Wednesday and Sunday"

  plan='{"version":1,"days":[{"kind":"train","sport":"run"},{"kind":"rest"},{"kind":"train","sport":"custom","customSport":" 飞盘 "},{"kind":"rest"},{"kind":"train"},{"kind":"rest"},{"kind":"train","sport":"run"}]}'
  call PUT "/me/weekly-plans/$next" "$planner_token" "$plan"
  expect 200
  saved="$(jq -c .days <<<"$body")"
  [ "$(jq -c '[.source, .days[2].customSport]' <<<"$body")" = '["saved","飞盘"]' ] || fail "next week should be saved, sport trimmed: $body"
  call PUT "/me/weekly-plans/$next" "$planner_token" "$plan"
  expect 200
  [ "$(jq -c .days <<<"$body")" = "$saved" ] || fail "saving again changed the plan: $body"
  echo "weekly-plan: next week ($next) saved, custom sport trimmed; saving again changes nothing"

  later="$(days_after "$monday" 14)"
  call GET "/me/weekly-plans/$later" "$planner_token"
  expect 200
  [ "$(jq -c '[.source, .days]' <<<"$body")" = "[\"carriedOver\",$saved]" ] || fail "the week after should carry next week's plan over: $body"
  echo "weekly-plan: the week after ($later) carries it over"

  call PUT "/me/weekly-plans/$(days_after "$monday" -7)" "$planner_token" "$plan"
  expect 400 WEEK_OVER
  call PUT "/me/weekly-plans/$(days_after "$monday" 35)" "$planner_token" "$plan"
  expect 400 WEEK_TOO_FAR_AHEAD
  call GET "/me/weekly-plans/$(days_after "$monday" 1)" "$planner_token"
  expect 400 REQUEST_INVALID
  echo "weekly-plan: last week refused (400 WEEK_OVER), 5 weeks ahead refused (400 WEEK_TOO_FAR_AHEAD), a Tuesday refused (400)"

  rows="$(psql "$DB_URL" -tAc "select count(*) from public.weekly_plans where member_id = '$planner'")"
  [ "$rows" = 1 ] || fail "only next week should be stored: $rows rows"
  echo "weekly-plan: one row stored, for $next"
fi

if want squad-today; then
  # A squad of its own, so the other journeys' check-ins don't count here; the shared one comes
  # back at the end. Runner and napper plan to train every day, rester to rest every day.
  shared_squad="$squad"
  read -r runner runner_token <<<"$(sign_up)"
  read -r napper napper_token <<<"$(sign_up)"
  read -r rester rester_token <<<"$(sign_up)"
  read -r zone today monday <<<"$(noon_zone)"
  for token in "$runner_token" "$napper_token" "$rester_token"; do
    call PUT /me/profile "$token" "{\"version\":1,\"timeZone\":\"$zone\"}"
    expect 200
  done
  # The runner picks a catchphrase (口头禅) and makes a character; the napper's catchphrases are
  # refused, so theirs stays unset.
  runner_look='{"persona":"energetic","variants":{"body":"shiba","top":"jersey"},"colors":{"top":"#2D5BA0"}}'
  call PUT /me/profile "$runner_token" "{\"version\":1,\"timeZone\":\"$zone\",\"catchphrase\":\" 冲就完了🔥 \",\"character\":{\"nickname\":\" 跑跑 \",\"look\":$runner_look}}"
  expect 200
  [ "$(jq -r .catchphrase <<<"$body")" = '冲就完了🔥' ] || fail "the catchphrase should be saved trimmed: $body"
  # Compared with sorted keys: the database keeps JSON objects in its own key order.
  [ "$(jq -cS .character <<<"$body")" = "$(jq -cS --argjson look "$runner_look" -n '{nickname: "跑跑", look: $look}')" ] ||
    fail "the character should be saved with its nickname trimmed: $body"
  call PUT /me/profile "$napper_token" "{\"version\":1,\"timeZone\":\"$zone\",\"catchphrase\":\"今天也是冲冲冲的一天!\"}"
  expect 400 REQUEST_INVALID
  call PUT /me/profile "$napper_token" "{\"version\":1,\"timeZone\":\"$zone\",\"catchphrase\":\"看abc.com\"}"
  expect 400 REQUEST_INVALID
  echo "squad-today: runner's catchphrase 冲就完了🔥 and character 跑跑 saved; napper's 11 characters and link refused (400)"
  squad_of "$runner_token" "$napper_token" "$rester_token"
  plan_of() { jq -cn --arg kind "$1" '{version: 1, days: [range(7) | {kind: $kind}]}'; }
  for token in "$runner_token" "$napper_token"; do
    call PUT "/me/weekly-plans/$monday" "$token" "$(plan_of train)"
    expect 200
  done
  call PUT "/me/weekly-plans/$monday" "$rester_token" "$(plan_of rest)"
  expect 200
  call PUT "/check-ins/$(new_id)" "$runner_token" "$(check_in_of "$squad" "$today" trained '"training":{"sport":"run"}')"
  expect 201
  call PUT "/check-ins/$(new_id)" "$runner_token" "$(check_in_of "$squad" "$today" healthyMeal '"meal":{"caption":"沙拉"}')"
  expect 201
  # A minute before the runner's check-ins, however long the earlier journeys took: the napper
  # checked in first today.
  earlier="$(node -p "new Date(Date.parse('$now') - 60_000).toISOString()")"
  call PUT "/check-ins/$(new_id)" "$napper_token" "$(check_in_of "$squad" "$today" disclaimer '"disclaimer":{"text":"腿还在酸"}' | sed "s/$now/$earlier/")"
  expect 201
  echo "squad-today: in $zone ($today) runner trained and ate a healthy meal, napper posted a disclaimer first, rester plans to rest"

  call GET "/squads/$squad/today" "$napper_token"
  expect 200
  [ "$(jq -c '[.members[] | [.member, .day, .training, .latestMeal, .plannedRest, .firstCheckInAt != null]]' <<<"$body")" = \
    "$(jq -cn --arg a "$runner" --arg b "$napper" --arg c "$rester" --arg d "$today" \
      '[[$b,$d,"disclaimer",null,false,true],[$a,$d,"trained","healthyMeal",false,true],[$c,$d,"notCheckedIn",null,true,false]]')" ] ||
    fail "members should be napper (first check-in), runner, then rester (planned rest): $body"
  [ "$(jq -c '[.today, .me.week.trainedDays, .me.week.plannedDays, .me.lifetimeTrainedDays, .squadWeek]' <<<"$body")" = \
    '[{"trained":1,"disclaimer":1,"resting":1,"everyoneTrained":false},0,7,0,{"trainedDays":1,"plannedDays":14}]' ] ||
    fail "counts should be 1 trained, 1 disclaimer, 1 resting; napper 0/7; squad 1/14: $body"
  echo "squad-today: napper sees self first, then runner, then rester; 1 trained, 1 disclaimer, 1 resting; 本周 0/7, squad 1/14"
  [ "$(jq -c '[.members[] | .catchphrase]' <<<"$body")" = '[null,"冲就完了🔥",null]' ] ||
    fail "squadmates should see the runner's catchphrase, and null for the others: $body"
  echo "squad-today: napper sees runner's catchphrase 冲就完了🔥, null for self and rester"
  [ "$(jq -cS '[.members[] | .character]' <<<"$body")" = "$(jq -cS --argjson look "$runner_look" -n '[null, {nickname: "跑跑", look: $look}, null]')" ] ||
    fail "squadmates should see the runner's character, and none for the others: $body"
  echo "squad-today: napper sees runner's character 跑跑 (shiba in a jersey), none for self and rester"

  call PUT "/check-ins/$(new_id)" "$napper_token" "$(check_in_of "$squad" "$today" trained '"training":{"sport":"run"}')"
  expect 201
  call GET "/squads/$squad/today" "$napper_token"
  expect 200
  [ "$(jq -c '[.members[0].training, .today, .me.week.trainedDays, .squadWeek]' <<<"$body")" = \
    '["trained",{"trained":2,"disclaimer":0,"resting":1,"everyoneTrained":true},1,{"trainedDays":2,"plannedDays":14}]' ] ||
    fail "napper's 练了 should win over the disclaimer, and the rester's rest day count toward everyone: $body"
  echo "squad-today: napper trained after all, so 练了 wins over the disclaimer; with rester resting, everyone trained"

  call GET "/squads/$squad/today" "$outsider_token"
  expect 403 SQUAD_NOT_JOINED
  echo "squad-today: outsider refused (403 SQUAD_NOT_JOINED)"
  squad="$shared_squad"
fi

if want week-summary; then
  # A squad of its own for this week's 战报. Ace plans a week of rest, so one 练了 completes it;
  # the writer posts a 请假条 and the fan laughs at it.
  shared_squad="$squad"
  read -r ace ace_token <<<"$(sign_up)"
  read -r writer writer_token <<<"$(sign_up)"
  read -r fan fan_token <<<"$(sign_up)"
  read -r zone today monday <<<"$(noon_zone)"
  for token in "$ace_token" "$writer_token" "$fan_token"; do
    call PUT /me/profile "$token" "{\"version\":1,\"timeZone\":\"$zone\"}"
    expect 200
  done
  squad_of "$ace_token" "$writer_token" "$fan_token"
  call PUT "/me/weekly-plans/$monday" "$ace_token" "$(jq -cn '{version: 1, days: [range(7) | {kind: "rest"}]}')"
  expect 200
  call PUT "/check-ins/$(new_id)" "$ace_token" "$(check_in_of "$squad" "$today" trained '"training":{"sport":"run"}')"
  expect 201
  excuse="$(new_id)"
  call PUT "/check-ins/$excuse" "$writer_token" "$(check_in_of "$squad" "$today" disclaimer '"disclaimer":{"text":"腿还在酸"}')"
  expect 201
  call PUT "/check-ins/$excuse/reactions/mine" "$fan_token" '{"version":1,"kind":"lol"}'
  expect 201
  echo "week-summary: squad=$squad in $zone ($today) ace trained on a week planned all rest, writer posted a 请假条, fan laughed at it"

  call GET "/squads/$squad/weeks/$monday/summary" "$fan_token"
  expect 200
  [ "$(jq -c '[.final, [.awards[] | [.kind, [.winners[] | [.member, .value, .checkIn]]]]]' <<<"$body")" = \
    "$(jq -cn --arg a "$ace" --arg w "$writer" --arg e "$excuse" \
      '[false, [["planCompleted",[[$a,1,null]]],["crown",[[$a,1,null]]],["bestDisclaimer",[[$w,1,$e]]]]]')" ] ||
    fail "ace should complete the plan and wear the crown, and the writer's 请假条 be the best; not final yet: $body"
  echo "week-summary: still being played; podium and crown ace (1 day), best 请假条 writer's (1 reaction)"
  [ "$(jq -c '[[.squadTotals.stats[] | select(.kind == "trainedDays" or .kind == "plannedDays" or .kind == "checkIns") | .value], [.squadTotals.reactions[] | select(.kind == "lol") | .count], [.me.reactions[] | select(.kind == "lol") | .given]]' <<<"$body")" = \
    '[[1,10,2],[1],[1]]' ] ||
    fail "the squad should have 1 of 10 days trained in 2 check-ins and 1 lol, given by the fan: $body"
  echo "week-summary: squad 1/10 days in 2 check-ins, 1 笑死, which the fan sees as given"

  call GET "/squads/$squad/weeks/$(days_after "$monday" 7)/summary" "$fan_token"
  expect 400 WEEK_NOT_STARTED
  call GET "/squads/$squad/weeks/$monday/summary" "$outsider_token"
  expect 403 SQUAD_NOT_JOINED
  echo "week-summary: next week refused (400 WEEK_NOT_STARTED), outsider refused (403 SQUAD_NOT_JOINED)"
  squad="$shared_squad"
fi

if want reactions; then
  post="$(new_id)"
  call PUT "/check-ins/$post" "$me_token" "$(check_in_of "$squad" "$day" trained '"training":{"sport":"run"}')"
  expect 201
  reaction() { echo "{\"version\":1,\"kind\":\"$1\"}"; }
  call PUT "/check-ins/$post/reactions/mine" "$mate_token" "$(reaction cheer)"
  expect 201
  call PUT "/check-ins/$post/reactions/mine" "$mate_token" "$(reaction cheer)"
  expect 200
  call PUT "/check-ins/$post/reactions/mine" "$mate_token" "$(reaction lol)"
  expect 200
  echo "reactions: mate cheered (201), again (200), then changed it to lol (200)"

  call GET "/check-ins/$post/reactions" "$me_token"
  expect 200
  [ "$(jq -c '[.reactions[] | [.member, .kind]]' <<<"$body")" = "$(jq -cn --arg m "$mate" '[[$m,"lol"]]')" ] ||
    fail "the author should see one reaction, mate's lol: $body"
  echo "reactions: the author sees one reaction, mate's lol"

  call PUT "/check-ins/$post/reactions/mine" "$me_token" "$(reaction cheer)"
  expect 400 OWN_CHECK_IN_REACTION
  call PUT "/check-ins/$post/reactions/mine" "$outsider_token" "$(reaction cheer)"
  expect 404 CHECK_IN_NOT_FOUND
  call GET "/check-ins/$post/reactions" "$outsider_token"
  expect 404 CHECK_IN_NOT_FOUND
  call PUT "/check-ins/$post/reactions/mine" "$mate_token" "$(reaction 稳)"
  expect 400 REQUEST_INVALID
  echo "reactions: own check-in refused (400 OWN_CHECK_IN_REACTION), outsider sees nothing (404), unknown kind refused (400)"

  call DELETE "/check-ins/$post/reactions/mine" "$mate_token"
  expect 204
  call DELETE "/check-ins/$post/reactions/mine" "$mate_token"
  expect 204
  rows="$(psql "$DB_URL" -tAc "select count(*) from public.check_in_reactions where check_in_id = '$post'")"
  [ "$rows" = 0 ] || fail "the reaction should be gone: $rows rows"
  echo "reactions: mate took it off (204, again 204), no row left"
fi

if want devices; then
  phone="$(node -p 'crypto.randomBytes(32).toString("hex")')"
  owner_of() { psql "$DB_URL" -tAc "select member_id || ' ' || environment from public.push_devices where token = '$phone'"; }
  call PUT /me/devices "$me_token" "{\"version\":1,\"token\":\"$phone\",\"environment\":\"sandbox\"}"
  expect 200
  call PUT /me/devices "$me_token" "{\"version\":1,\"token\":\"$phone\",\"environment\":\"sandbox\"}"
  expect 200
  [ "$(owner_of)" = "$me sandbox" ] || fail "the phone should be me's, sandbox: $(owner_of)"
  echo "devices: me registered a phone (200, again 200)"

  call PUT /me/devices "$mate_token" "{\"version\":1,\"token\":\"$phone\",\"environment\":\"production\"}"
  expect 200
  [ "$(owner_of)" = "$mate production" ] || fail "the phone should move to mate: $(owner_of)"
  echo "devices: mate signed in on the same phone, so it moved to mate"

  call POST /me/devices/remove "$me_token" "{\"version\":1,\"token\":\"$phone\"}"
  expect 204
  [ "$(owner_of)" = "$mate production" ] || fail "me removing mate's phone changed it: $(owner_of)"
  call POST /me/devices/remove "$mate_token" "{\"version\":1,\"token\":\"$phone\"}"
  expect 204
  [ -z "$(owner_of)" ] || fail "the phone should be gone: $(owner_of)"
  echo "devices: me removing it did nothing (204); mate signing out removed it (204)"

  call PUT /me/devices "$me_token" '{"version":1,"token":"not-hex","environment":"sandbox"}'
  expect 400 REQUEST_INVALID
  echo "devices: a token that isn't hex refused (400)"
fi

if want account; then
  read -r leaver leaver_token <<<"$(sign_up)"
  call GET /me "$leaver_token"
  expect 200
  [ "$(jq -c . <<<"$body")" = "$(jq -cn --arg m "$leaver" '{version:1,userId:$m,profile:null}')" ] || fail "a new member has no profile: $body"
  call PUT /me/profile "$leaver_token" '{"version":1,"timeZone":"Mars/Olympus_Mons"}'
  expect 400 TIME_ZONE_UNKNOWN
  call PUT /me/profile "$leaver_token" '{"version":1,"timeZone":"America/Toronto"}'
  expect 200
  call GET /me "$leaver_token"
  expect 200
  [ "$(jq -c .profile <<<"$body")" = '{"timeZone":"America/Toronto","catchphrase":null}' ] || fail "the profile should be saved: $body"
  echo "account: a new member has no profile, an unknown zone is refused (400 TIME_ZONE_UNKNOWN), America/Toronto saved"

  squad_of "$leaver_token" "$mate_token"
  call POST /photo-uploads "$leaver_token"
  expect 201
  path="$(jq -r .path <<<"$body")"
  curl -sf -X PUT "$(jq -r .uploadUrl <<<"$body")" -H 'content-type: image/jpeg' --data-binary 'not really a jpeg' >/dev/null ||
    fail "upload to storage failed"
  # The leaver's own day in Toronto when the check-in was made, which lasts until 3am there.
  toronto_day="$(node -p "new Date(Date.parse('$now') - 3 * 3_600_000).toLocaleDateString('en-CA', { timeZone: 'America/Toronto' })")"
  call PUT "/check-ins/$(new_id)" "$leaver_token" "$(check_in_of "$squad" "$toronto_day" healthyMeal "\"meal\":{\"photos\":[{\"path\":\"$path\"}]}")"
  expect 201
  echo "account: leaver made a squad with mate and posted a meal with a photo"

  call DELETE /me "$leaver_token" '{"version":1}'
  expect 204
  left="$(psql "$DB_URL" -tAc "select
      (select count(*) from auth.users where id = '$leaver') || ' ' ||
      (select count(*) from public.profiles where member_id = '$leaver') || ' ' ||
      (select count(*) from public.check_ins where member_id = '$leaver') || ' ' ||
      (select count(*) from public.squad_members where member_id = '$leaver') || ' ' ||
      (select count(*) from storage.objects where name like '$leaver/%') || ' ' ||
      (select count(*) from public.squad_members where squad_id = '$squad')")"
  [ "$left" = "0 0 0 0 0 1" ] || fail "user, profile, check-ins, memberships, photos should be gone and the squad left to mate: $left"
  echo "account: deleted (204): no user, profile, check-in, membership or photo left; the squad stays with mate"

  call DELETE /me "$leaver_token" '{"version":1}'
  expect 401
  echo "account: deleting again with the old token refused (401)"
fi

if want admin-mcp; then
  # An MCP client registered by hand, as an admin registers Claude Code or claude.ai: dynamic
  # registration is off.
  callback="http://localhost:9999/callback"
  registered="$(curl -s "$API_URL/auth/v1/admin/oauth/clients" -H "apikey: $SECRET_KEY" \
    -H "authorization: Bearer $SECRET_KEY" -H 'content-type: application/json' \
    --data "{\"client_name\":\"api-journeys\",\"redirect_uris\":[\"$callback\"],\"token_endpoint_auth_method\":\"none\",\"grant_types\":[\"authorization_code\",\"refresh_token\"],\"response_types\":[\"code\"]}")"
  client_id="$(jq -r '.client_id // empty' <<<"$registered")"
  # Supabase reads [auth.oauth_server] at `supabase start`: a stack started before it was
  # enabled answers "OAuth server is disabled" until it restarts.
  [[ "$client_id" =~ ^[0-9a-f-]{36}$ ]] || fail "registering the MCP client failed: $registered"
  # sign_up_as EMAIL PASSWORD: like sign_up, with credentials the consent page can take.
  sign_up_as() {
    curl -sf "$API_URL/auth/v1/signup" -H "apikey: $PUBLISHABLE_KEY" -H 'content-type: application/json' \
      --data "{\"email\":\"$1\",\"password\":\"$2\"}" | jq -r '"\(.user.id) \(.access_token)"'
  }
  admin_email="$(new_id)@example.com" admin_password="$(new_id)"
  read -r admin admin_token <<<"$(sign_up_as "$admin_email" "$admin_password")"
  member_email="$(new_id)@example.com" member_password="$(new_id)"
  read -r member member_token <<<"$(sign_up_as "$member_email" "$member_password")"
  [[ "$admin $member" =~ ^[0-9a-f-]{36}\ [0-9a-f-]{36}$ ]] || fail "sign-up failed"
  psql "$DB_URL" -qc "insert into public.admins (member_id) values ('$admin')" >/dev/null
  echo "admin-mcp: registered client $client_id; admin=$admin on the admin list"

  # mcp TOKEN BODY: one JSON-RPC message to /mcp; sets $code, $body (the JSON-RPC answer, read
  # out of the event stream when it is one) and $challenge (the WWW-Authenticate header).
  mcp() {
    local args=(-s -D "$tmp/headers" -o "$tmp/body" -w '%{http_code}' -X POST "$api/mcp"
      -H 'content-type: application/json' -H 'accept: application/json, text/event-stream'
      -H 'mcp-protocol-version: 2025-06-18' --data "$2")
    [ -n "$1" ] && args+=(-H "authorization: Bearer $1")
    code="$(curl "${args[@]}")"
    challenge="$(tr -d '\r' <"$tmp/headers" | sed -n 's/^www-authenticate: //Ip')"
    body="$(sed -n 's/^data: //p' "$tmp/body")"
    [ -n "$body" ] || body="$(cat "$tmp/body")"
  }
  initialize='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"api-journeys","version":"1"}}}'

  mcp "" "$initialize"
  expect 401 AUTH_TOKEN_MISSING
  metadata_url="$(sed -n 's/.*resource_metadata="\([^"]*\)".*/\1/p' <<<"$challenge")"
  [ "$metadata_url" = "$api/.well-known/oauth-protected-resource/mcp" ] || fail "401 doesn't point at the metadata: $challenge"
  metadata="$(curl -sf "$metadata_url")"
  [ "$(jq -r '.resource + " " + .authorization_servers[0]' <<<"$metadata")" = "$api/mcp $API_URL/auth/v1" ] ||
    fail "metadata should name /mcp and Supabase Auth: $metadata"
  echo "admin-mcp: no token refused (401), pointing at metadata that names Supabase Auth"

  mcp "$admin_token" "$initialize"
  expect 401 ADMIN_SIGN_IN_REQUIRED
  echo "admin-mcp: the app's own sign-in refused (401 ADMIN_SIGN_IN_REQUIRED)"

  # authorize: the client asks Supabase Auth's OAuth 2.1 server for approval with PKCE, as an
  # MCP client does; sets $id (the request the consent page answers) and $verifier.
  authorize() {
    local challenge_s256 location
    verifier="$(node -p 'crypto.randomBytes(32).toString("base64url")')"
    challenge_s256="$(node -p "crypto.createHash('sha256').update('$verifier').digest('base64url')")"
    location="$(curl -s -o /dev/null -w '%{redirect_url}' -G "$API_URL/auth/v1/oauth/authorize" \
      --data-urlencode response_type=code --data-urlencode "client_id=$client_id" \
      --data-urlencode "redirect_uri=$callback" --data-urlencode "code_challenge=$challenge_s256" \
      --data-urlencode code_challenge_method=S256 --data-urlencode "resource=$api/mcp")"
    id="$(node -p "new URL('$location').searchParams.get('authorization_id') ?? ''")"
    [ -n "$id" ] || fail "authorize didn't send the member to the consent page: $location"
  }
  # sign_in_on_page EMAIL PASSWORD: signs in on the consent page for $id, as a browser does;
  # sets $code and $page (the HTML it answered), keeping its cookie in $jar.
  jar="$tmp/consent-cookies"
  sign_in_on_page() {
    rm -f "$jar"
    code="$(curl -s -o "$tmp/page" -w '%{http_code}' -c "$jar" -b "$jar" "$api/oauth/consent/sign-in" \
      --data-urlencode "authorization_id=$id" --data-urlencode "email=$1" --data-urlencode "password=$2")"
    page="$(cat "$tmp/page")"
  }
  # token_for REDIRECT: the access token for the code the browser was sent back with.
  token_for() {
    local authorization_code
    authorization_code="$(node -p "new URL('$1').searchParams.get('code') ?? ''")"
    [ -n "$authorization_code" ] || fail "the browser wasn't sent back with a code: $1"
    curl -s -X POST "$API_URL/auth/v1/oauth/token" --data-urlencode grant_type=authorization_code \
      --data-urlencode "code=$authorization_code" --data-urlencode "redirect_uri=$callback" \
      --data-urlencode "client_id=$client_id" --data-urlencode "code_verifier=$verifier" \
      --data-urlencode "resource=$api/mcp" | jq -r '.access_token // empty'
  }

  authorize
  sign_in_on_page "$admin_email" wrong-password
  [ "$code" = 401 ] && [[ "$page" == *"Wrong email or password."* ]] || fail "a wrong password: $code $page"
  sign_in_on_page "$admin_email" "$admin_password"
  [ "$code" = 200 ] && [[ "$page" == *"Let api-journeys manage Wildcard?"* ]] || fail "the consent page: $code $page"
  answered="$(curl -s -o /dev/null -w '%{redirect_url}' -b "$jar" "$api/oauth/consent/answer" \
    --data-urlencode "authorization_id=$id" --data-urlencode answer=approve)"
  mcp_token="$(token_for "$answered")"
  [ -n "$mcp_token" ] || fail "the OAuth token exchange failed"
  echo "admin-mcp: a wrong password refused (401); admin signed in on the consent page, approved and got an OAuth token"

  again="$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "$api/oauth/consent/answer" \
    --data-urlencode "authorization_id=$id" --data-urlencode answer=approve)"
  [ "$again" = 401 ] || fail "the consent page's sign-in answered twice: $again"
  echo "admin-mcp: that sign-in can't answer again (401)"

  mcp "$mcp_token" "$initialize"
  expect 200
  [ "$(jq -r .result.serverInfo.name <<<"$body")" = wildcard-admin ] || fail "initialize: $body"
  mcp "$mcp_token" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  expect 200
  tools="$(jq -r '[.result.tools[].name] | join(",")' <<<"$body")"
  [ "$tools" = "list_admin_log,list_memes,add_memes,turn_off_meme,turn_on_meme" ] || fail "tools: $body"
  echo "admin-mcp: initialized and listed the tools ($tools)"

  # tool NAME ARGUMENTS: calls a tool; sets $result (the text it answered) and $is_error.
  tool() {
    mcp "$mcp_token" "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
    expect 200
    result="$(jq -r '.result.content[0].text' <<<"$body")"
    is_error="$(jq -r '.result.isError // false' <<<"$body")"
  }
  phrase="班味$(new_id | cut -c1-8)"
  tool add_memes "{\"memes\":[{\"phrase\":\"$phrase\",\"background\":\"上班上久了，人身上带着的那股疲惫劲儿。\",\"meaning\":\"一看就是打工人。\",\"styles\":[\"funny\"],\"source\":\"小红书\"}]}"
  [ "$(jq -c '[.added, .alreadyThere]' <<<"$result")" = "[[\"$phrase\"],[]]" ] || fail "add_memes: $result"
  tool list_memes '{}'
  jq -e --arg p "$phrase" '.memes | any(.phrase == $p)' <<<"$result" >/dev/null || fail "$phrase isn't in use: $result"
  echo "admin-mcp: added the meme $phrase and it is in use"

  tool turn_off_meme "{\"phrase\":\"$phrase\"}"
  [ "$is_error" = false ] || fail "turn_off_meme: $result"
  tool list_memes '{}'
  jq -e --arg p "$phrase" '.memes | all(.phrase != $p)' <<<"$result" >/dev/null || fail "$phrase is still in use: $result"
  tool turn_off_meme '{"phrase":"没这个梗"}'
  [ "$is_error $result" = "true MEME_NOT_FOUND: The meme library has no 「没这个梗」." ] || fail "missing meme: $result"
  echo "admin-mcp: turned it off, so it is no longer in use; an unknown meme refused (MEME_NOT_FOUND)"

  tool list_admin_log '{}'
  [ "$(jq -r '[.changes[].tool] | join(",")' <<<"$result")" = "turn_off_meme,add_memes" ] || fail "admin log: $result"
  logged="$(psql "$DB_URL" -tAc "select string_agg(action->>'tool', ',' order by id) from public.admin_actions where admin_id = '$admin'")"
  [ "$logged" = "add_memes,turn_off_meme" ] || fail "admin_actions should hold the two changes, not the reads or the refusal: $logged"
  echo "admin-mcp: the log holds the two changes, newest first, and no reads ($logged)"

  call GET /me "$mcp_token"
  expect 401 APP_SIGN_IN_REQUIRED
  echo "admin-mcp: the OAuth token refused by the app's routes (401 APP_SIGN_IN_REQUIRED)"

  authorize
  sign_in_on_page "$member_email" "$member_password"
  [ "$code" = 403 ] && [[ "$page" == *"isn’t an admin"* ]] || fail "a member not on the admin list: $code $page"
  echo "admin-mcp: a member not on the admin list refused on the consent page (403)"

  # Approving with their app session straight through Supabase's API, as a stolen session could.
  authorizations="$API_URL/auth/v1/oauth/authorizations/$id"
  curl -sf "$authorizations" -H "apikey: $PUBLISHABLE_KEY" -H "authorization: Bearer $member_token" >/dev/null ||
    fail "reading the authorization request failed"
  answered="$(curl -s -X POST "$authorizations/consent" -H "apikey: $PUBLISHABLE_KEY" \
    -H "authorization: Bearer $member_token" -H 'content-type: application/json' --data '{"action":"approve"}' |
    jq -r '.redirect_url // empty')"
  member_mcp_token="$(token_for "$answered")"
  [ -n "$member_mcp_token" ] || fail "the member's OAuth token exchange failed"
  mcp "$member_mcp_token" "$initialize"
  expect 403 NOT_AN_ADMIN
  echo "admin-mcp: approving around the page still gets them nothing at /mcp (403 NOT_AN_ADMIN)"
fi

echo "api-journeys: ok ($journeys)"
