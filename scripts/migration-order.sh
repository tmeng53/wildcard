#!/usr/bin/env bash
# Fails when a migration this branch adds is numbered at or below the newest one on its base.
# The hosted database refuses a migration older than the last one it ran, so an out-of-order
# number passes local `supabase db reset` and then fails the deploy (#459, #480, #537, #577, #580).
# Usage: scripts/migration-order.sh [base-commit]   (default origin/main; CI passes the base
# branch's tip as MIGRATIONS_BASE through scripts/verify.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

base="${1:-origin/main}"
dir=supabase/migrations
# CI checks out one commit, so fetch the base when it isn't here.
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  if [ "$base" = origin/main ]; then
    git fetch --quiet --depth=1 origin '+refs/heads/main:refs/remotes/origin/main' || true
  else
    git fetch --quiet --no-tags --depth=1 origin "$base" || true
  fi
fi
if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "migration order: base $base is not in this clone" >&2
  exit 1
fi

# File names only; a migration's version is the digits before its first underscore.
names() { sort -u | sed -n 's|^.*/||p'; }
on_base="$(git ls-tree --name-only "$base" -- "$dir/" | names)"
here="$( { git ls-files -- "$dir/"; git ls-files --others --exclude-standard -- "$dir/"; } | names)"
version() { sed -n 's/^\([0-9]\{1,\}\)_.*\.sql$/\1/p'; }

failed=0
# Every file needs a numeric version, and no two may share one.
bad="$(grep -v '^[0-9]\{1,\}_.*\.sql$' <<<"$here" || true)"
if [ -n "$bad" ]; then
  echo "migration order: these files have no <version>_<name>.sql name:" >&2
  sed 's/^/  /' <<<"$bad" >&2
  failed=1
fi
dupes="$(version <<<"$here" | sort | uniq -d)"
if [ -n "$dupes" ]; then
  echo "migration order: more than one migration has version $(paste -sd, <<<"$dupes")" >&2
  failed=1
fi

# The newest version on the base that this branch still has (a renumbering PR moves one away).
kept="$(comm -12 <(printf '%s\n' "$on_base") <(printf '%s\n' "$here"))"
newest="$(version <<<"$kept" | sort | tail -n 1)"
added="$(comm -13 <(printf '%s\n' "$on_base") <(printf '%s\n' "$here") | sed '/^$/d')"
while IFS= read -r file; do
  [ -n "$file" ] || continue
  v="$(version <<<"$file")"
  [ -n "$v" ] || continue
  # Same-length timestamps compare as strings; a shorter or longer version is out of order too.
  if [ -n "$newest" ] && { [ "${#v}" -ne "${#newest}" ] || [[ ! "$v" > "$newest" ]]; }; then
    echo "migration order: $file must be numbered after $newest, the newest on $base;" \
      "rename it to a later timestamp" >&2
    failed=1
  fi
done <<<"$added"

[ "$failed" = 0 ] || exit 1
echo "migration order: ok ($(grep -c . <<<"$added" || true) new after ${newest:-none})"
