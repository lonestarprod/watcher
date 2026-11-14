#!/usr/bin/env bash
# The offline suite for bin/check-old-owner.sh: a scratch git repo per case, no network.
#   bash bin/test-check-old-owner.sh      # exit 0 = all cases hold
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/check-old-owner.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0; cases=0
check() { cases=$((cases+1)); if "${@:2}"; then printf '  %-70s ok\n' "$1"; else printf '  %-70s FAIL\n' "$1"; fails=$((fails+1)); fi; }

# The old owner's name is split so this file does not trip the gate it tests.
O="rol""oc"

repo() {  # repo <name>: an empty scratch repo; prints its path
  local d="$TMP/$1"; mkdir -p "$d"; git -C "$d" init -q; echo "$d"
}
run() {   # run <dir>: sets OUT and RC
  OUT="$(cd "$1" && bash "$GATE" 2>&1)"; RC=$?
}
add() { git -C "$1" add -A; }

echo "1. a clean checkout passes — the bare login, the App names and made-up repos are not addresses"
d="$(repo clean)"
printf '%s\n' "OWNER_LOGIN=$O" "$O-desk-author[bot]" "~/.config/$O-apps/desk/" "Needs @$O: one question?" \
  "PROJECT_REPO=$O/testproj" "https://github.com/$O/alpha/issues/7" "--from $O/4" \
  "https://github.com/lonestarprod/watcher" "https://github.com/orgs/lonestarprod/projects/1" > "$d/a.txt"
add "$d"; run "$d"
check "exit 0" [ "$RC" -eq 0 ]

echo "2. each real repo under the old owner fails, naming the file and the line"
for r in watcher riffmap riffmap-site NullTrader nulltrader azeroth-rewind playbook; do
  d="$(repo "bad-$r")"; mkdir -p "$d/docs"
  printf '%s\n' "fine" "see https://github.com/$O/$r/issues/1" > "$d/docs/x.md"
  add "$d"; run "$d"
  check "$r: exit 1" [ "$RC" -eq 1 ]
  check "$r: names docs/x.md line 2" grep -q "docs/x.md:2 " <<<"$OUT"
done

echo "3. the other spellings of an address fail too"
for s in "gh issue view 1 -R $O/watcher" "repos/$O/watcher/actions/runs" "git@github.com:$O/watcher.git" \
         "\"default\": \"$O/watcher\"" "https://github.com/users/$O/projects/1"; do
  d="$(repo "sp-$cases")"; printf '%s\n' "$s" > "$d/f"; add "$d"; run "$d"
  check "$s" [ "$RC" -eq 1 ]
done

echo "4. only tracked files count, and a search that could not run is a failure, never 'clean'"
d="$(repo untracked)"; echo ok > "$d/a"; add "$d"; echo "$O/watcher" > "$d/scratch.txt"; run "$d"
check "an untracked file is not read" [ "$RC" -eq 0 ]
mkdir -p "$TMP/norepo"; OUT="$(cd "$TMP/norepo" && GIT_CEILING_DIRECTORIES="$TMP" bash "$GATE" 2>&1)"; RC=$?
check "outside a checkout: exit 2, not 0" [ "$RC" -eq 2 ]
d="$(repo broken)"; echo "$O/watcher" > "$d/a"; add "$d"; rm -rf "$d/.git/objects"
run "$d"
check "a checkout git cannot read: not exit 0" [ "$RC" -ne 0 ]

echo "5. this repo itself is clean"
OUT="$(cd "$HERE/.." && bash "$GATE" 2>&1)"; RC=$?
check "bin/check-old-owner.sh passes here" [ "$RC" -eq 0 ]
[ "$RC" -eq 0 ] || printf '%s\n' "$OUT"

echo
if [ "$fails" -eq 0 ]; then echo "$cases cases, all ok"; else echo "$cases cases, $fails FAILED"; exit 1; fi
