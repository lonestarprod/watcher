#!/usr/bin/env bash
# Fail when a tracked file names a real repo or a board under the old owner.
#
# The repos and the boards moved to the lonestarprod organization on October 30, 2026.
# Several changes each fixed the handful of old addresses in front of them and left the
# rest, so this is a gate (CI's `verify` runs it on every PR and every push to main): one
# such address anywhere in a tracked file is a red build that names the file and the line.
#
# What it matches: <old owner>/<one of the real repos>, in any spelling of the address (a
# link, `-R`, an API path, a clone URL), and a user-form board address under the old owner.
# What it leaves alone, on purpose:
#   - the old owner's bare login and the App names built on it: they are still real (the
#     owner's own account, the Apps' prefix, the Mac's config directory);
#   - made-up repos in the offline suites (<old owner>/testproj, /alpha, /thing, …): they
#     are fixtures, never an address anyone follows.
# The old owner's name is split below so this file does not match itself.
#
#   bash bin/check-old-owner.sh      # run from anywhere inside the checkout; exit 0 = clean
set -uo pipefail

old_owner="rol""oc"
repos='watcher|riffmap|riffmap-site|NullTrader|azeroth-rewind|playbook'
pattern="(^|[^[:alnum:]_.-])${old_owner}/(${repos})|users/${old_owner}/projects"

cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null \
  || { echo "check-old-owner: not inside a git checkout, so nothing was checked" >&2; exit 2; }

# git grep: 0 = found, 1 = none, anything else = it could not search. Only 1 is "clean".
hits="$(git grep -nIiE "$pattern" -- .)"
rc=$?
if [ "$rc" -gt 1 ]; then
  echo "check-old-owner: git grep failed (exit $rc), so nothing was checked" >&2
  exit 2
fi
if [ "$rc" -eq 1 ]; then
  echo "check-old-owner: no repo or board under the old owner is named"
  exit 0
fi

printf '%s\n' "$hits" | while IFS= read -r hit; do
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  echo "::error file=$file,line=$line::$file:$line names a repo or board under the old owner; it is lonestarprod/<repo>, and a board is orgs/lonestarprod/projects/<n>"
done
echo "check-old-owner: $(printf '%s\n' "$hits" | wc -l | tr -d ' ') line(s) name a repo or board under the old owner" >&2
exit 1
