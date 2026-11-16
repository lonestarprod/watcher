#!/usr/bin/env bash
#
# Offline test for deploy/mac-setup.sh (card #288): the desk App's identity read from a fixture
# key folder, the settings file merged (other keys kept, the suspended login's GH_CONFIG_DIR gone),
# the profile line that puts the shim first on PATH only in a Claude session's shell, a dry
# run that writes nothing, and a second run that changes nothing. Card #301: the same line kept
# last in ~/.zshrc, the guard that fires when a session's shell snapshot is built, and the
# check that asks a fresh shell which gh it finds and fails loudly when it is not the shim.
#
# The shell the check asks is a stand-in (MAC_SETUP_ZSH): bash, sourcing the two profiles in
# zsh's order and then running the command — so the suite is the same on a Mac and on a Linux
# runner with no zsh. Case 14 asks the real zsh too, where there is one.
#
#   bash bin/test-mac-setup.sh      # exit 0 = every case holds
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/deploy/mac-setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0; n=0
say()   { printf '  %-84s %s\n' "$1" "$2"; }
pass()  { n=$((n+1)); say "$1" "ok"; }
flunk() { n=$((n+1)); fail=1; say "$1" "FAIL${2:+ — $2}"; }
check() { if eval "$2"; then pass "$1"; else flunk "$1" "${3:-}"; fi; }

HOME_DIR="$TMP/home"; mkdir -p "$HOME_DIR/.claude"
SETTINGS="$HOME_DIR/.claude/settings.json"
ZSHENV="$HOME_DIR/.zshenv"
ZSHRC="$HOME_DIR/.zshrc"
SHIM_LINE_RE='bin/shim:\$PATH'
# The stand-in for `zsh -ic <command>`: the profiles in zsh's order, then the command.
FAKE_ZSH="$TMP/fake-zsh"
cat > "$FAKE_ZSH" <<'EOZ'
#!/usr/bin/env bash
[ -f "$MAC_SETUP_ZSHENV" ] && . "$MAC_SETUP_ZSHENV"
[ -f "$MAC_SETUP_ZSHRC" ] && . "$MAC_SETUP_ZSHRC"
[ -n "${FAKE_ZSH_LATER:-}" ] && PATH="$FAKE_ZSH_LATER:$PATH"   # something that runs after both files
eval "$2"
EOZ
chmod +x "$FAKE_ZSH"
# The owner's real gh, where his ~/.zshrc puts it.
mkdir -p "$HOME_DIR/.local/bin"; printf '#!/bin/sh\necho real gh\n' > "$HOME_DIR/.local/bin/gh"; chmod +x "$HOME_DIR/.local/bin/gh"
export HOME="$HOME_DIR" MAC_SETUP_SETTINGS="$SETTINGS" MAC_SETUP_ZSHENV="$ZSHENV" MAC_SETUP_ZSHRC="$ZSHRC" MAC_SETUP_ZSH="$FAKE_ZSH" WATCHER_HOME="$ROOT"
unset GH_APP_DIR WATCHER_APP_PROJECT PROJECT_NAME CLAUDE_CODE_ENTRYPOINT CLAUDECODE ZDOTDIR FAKE_ZSH_LATER
# A PATH with the real gh on it and no shim: what a shell has before the profiles run.
export PATH="$HOME_DIR/.local/bin:$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'bin/shim$' | paste -sd: -)"
# which_gh <session|own> — the gh a shell finds after the profiles, started either way.
which_gh() { if [ "$1" = session ]; then CLAUDE_CODE_ENTRYPOINT=claude-desktop "$FAKE_ZSH" -ic 'command -v gh'; else "$FAKE_ZSH" -ic 'command -v gh'; fi; }
run() { "$SCRIPT" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }
envkey() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("env",{}).get(sys.argv[2],"<absent>"))' "$SETTINGS" "$1"; }

# The settings file as this Mac had it: the suspended machine account's login and identity, a
# plugin dir and a permissions block that must survive untouched.
cat > "$SETTINGS" <<'EOJ'
{
  "permissions": {"allow": ["Bash(ls:*)"]},
  "env": {
    "GH_CONFIG_DIR": "/Users/me/.config/gh-desk",
    "GIT_AUTHOR_NAME": "roloc-desk",
    "GIT_AUTHOR_EMAIL": "1+roloc-desk@users.noreply.github.com",
    "GIT_CONFIG_COUNT": "2",
    "GIT_CONFIG_KEY_0": "credential.helper",
    "GIT_CONFIG_VALUE_0": "",
    "GIT_CONFIG_KEY_1": "credential.helper",
    "GIT_CONFIG_VALUE_1": "!gh auth git-credential",
    "CLAUDE_CODE_PLUGIN_DIRS": "/Users/me/Projects/watcher/mods/owner-pane"
  },
  "model": "opus"
}
EOJ
cp "$SETTINGS" "$TMP/settings.before"
printf 'export EDITOR=vim\n' > "$ZSHENV"

echo "1. no desk App on this Mac: exit 1, says what to run first, writes nothing"
RC="$(run)"
check "exit 1 and the app-setup command named" '[ "$RC" = 1 ] && grep -q "app-setup.py desk --all-repos" "$TMP/err"' "rc=$RC $(cat "$TMP/err")"
check "the settings file is untouched" 'cmp -s "$SETTINGS" "$TMP/settings.before"'
check "the profile is untouched" '[ "$(cat "$ZSHENV")" = "export EDITOR=vim" ] && [ ! -e "$ZSHRC" ]'

echo "2. the App set up: settings merged, the profile line added"
mkdir -p "$HOME_DIR/.config/roloc-apps/desk"
cat > "$HOME_DIR/.config/roloc-apps/desk/config" <<'EOC'
AUTHOR_APP_ID=7777
AUTHOR_INSTALLATION_ID=8888
AUTHOR_SLUG=roloc-desk-author
AUTHOR_BOT_ID=9999
EOC
RC="$(run)"
check "exit 0, and it names the App" '[ "$RC" = 0 ] && grep -q "the desk App is roloc-desk-author\[bot\]" "$TMP/out"' "rc=$RC $(cat "$TMP/out" "$TMP/err")"
check "WATCHER_APP_PROJECT=desk, so the checkout's remote never picks the App" '[ "$(envkey WATCHER_APP_PROJECT)" = desk ]'
check "the commit identity is the App's" '[ "$(envkey GIT_AUTHOR_NAME)" = "roloc-desk-author[bot]" ] && [ "$(envkey GIT_AUTHOR_EMAIL)" = "9999+roloc-desk-author[bot]@users.noreply.github.com" ] && [ "$(envkey GIT_COMMITTER_NAME)" = "roloc-desk-author[bot]" ] && [ "$(envkey GIT_COMMITTER_EMAIL)" = "9999+roloc-desk-author[bot]@users.noreply.github.com" ]' "$(envkey GIT_AUTHOR_NAME) $(envkey GIT_COMMITTER_EMAIL)"
check "git's credential helper is the shim's" '[ "$(envkey GIT_CONFIG_VALUE_1)" = "!$ROOT/bin/shim/gh-credential" ] && [ "$(envkey GIT_CONFIG_KEY_1)" = credential.helper ] && [ "$(envkey GIT_CONFIG_COUNT)" = 2 ]' "$(envkey GIT_CONFIG_VALUE_1)"
check "GH_CONFIG_DIR (the suspended login) is gone" '[ "$(envkey GH_CONFIG_DIR)" = "<absent>" ]'
check "every other key is kept: the plugin dir, permissions, model" '[ "$(envkey CLAUDE_CODE_PLUGIN_DIRS)" = /Users/me/Projects/watcher/mods/owner-pane ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d[\"permissions\"]=={\"allow\":[\"Bash(ls:*)\"]} and d[\"model\"]==\"opus\" else 1)" "$SETTINGS"'
check "the settings file is still JSON a human can read (indented, one trailing newline)" 'python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" && [ "$(tail -c1 "$SETTINGS" | od -An -c | tr -d " ")" = "\\n" ] && grep -q "^  \"env\": {" "$SETTINGS"'
check "the profile keeps its own line and gains the guarded shim line" '[ "$(head -1 "$ZSHENV")" = "export EDITOR=vim" ] && grep -q "bin/shim:\$PATH" "$ZSHENV" && grep -q "WATCHER_APP_PROJECT" "$ZSHENV" && [ "$(wc -l < "$ZSHENV" | tr -d " ")" = 2 ]' "$(cat "$ZSHENV")"
check "the output says what to expect from the next session" 'grep -q "started from now on writes to GitHub as roloc-desk-author\[bot\]" "$TMP/out"' "$(cat "$TMP/out")"

check "~/.zshrc is made, the one line (card #301)" '[ "$(wc -l < "$ZSHRC" | tr -d " ")" = 1 ] && grep -q "$SHIM_LINE_RE" "$ZSHRC"' "$(cat "$ZSHRC" 2>&1)"
check "the check ran and says both shells are right" 'grep -q "^check: a Claude session.s shell finds $ROOT/bin/shim/gh: the shim is first" "$TMP/out" && grep -q "^check: your own terminal finds $HOME_DIR/.local/bin/gh: untouched" "$TMP/out"' "$(cat "$TMP/out")"

echo "3. the profile line, sourced: the shim leads PATH only in a Claude session's shell"
P1="$(WATCHER_APP_PROJECT=desk bash -c "source \"$ZSHENV\"; printf %s \"\$PATH\"")"
P2="$(bash -c "source \"$ZSHENV\"; printf %s \"\$PATH\"")"
P3="$(CLAUDE_CODE_ENTRYPOINT=claude-desktop bash -c "source \"$ZSHENV\"; printf %s \"\$PATH\"")"
P4="$(CLAUDECODE=1 bash -c "source \"$ZSHENV\"; printf %s \"\$PATH\"")"
check "with WATCHER_APP_PROJECT: bin/shim first" '[ "${P1#$ROOT/bin/shim:}" != "$P1" ]' "$P1"
check "without any of the three (the owner's own terminal): PATH untouched" '[ "$P2" = "$PATH" ]' "$P2"
check "with CLAUDE_CODE_ENTRYPOINT and no WATCHER_APP_PROJECT (a session's snapshot shell, card #301): bin/shim first" '[ "${P3#$ROOT/bin/shim:}" != "$P3" ]' "$P3"
check "with CLAUDECODE alone: bin/shim first" '[ "${P4#$ROOT/bin/shim:}" != "$P4" ]' "$P4"

echo "4. a second run changes nothing and says so"
cp "$SETTINGS" "$TMP/settings.once"; cp "$ZSHENV" "$TMP/zshenv.once"; cp "$ZSHRC" "$TMP/zshrc.once"
RC="$(run)"
check "exit 0, all three files byte-identical" '[ "$RC" = 0 ] && cmp -s "$SETTINGS" "$TMP/settings.once" && cmp -s "$ZSHENV" "$TMP/zshenv.once" && cmp -s "$ZSHRC" "$TMP/zshrc.once"'
check "…and all three reported unchanged" 'grep -q "^settings: .*: unchanged" "$TMP/out" && [ "$(grep -c "^profile: .*: unchanged" "$TMP/out")" = 2 ]' "$(cat "$TMP/out")"

echo "5. a moved checkout: the profile line is replaced, never doubled"
RC="$(WATCHER_HOME="$TMP/elsewhere" run)"
check "exit 1 when the checkout has no token script (WATCHER_HOME must be the watcher)" '[ "$RC" = 1 ]'
mkdir -p "$TMP/elsewhere/bin/shim" && cp "$ROOT/bin/gh-app-token.sh" "$TMP/elsewhere/bin/" && cp "$ROOT/bin/shim/gh" "$TMP/elsewhere/bin/shim/"
RC="$(WATCHER_HOME="$TMP/elsewhere" run)"
check "one shim line in each profile, pointing at the new checkout" '[ "$RC" = 0 ] && [ "$(grep -c "bin/shim:" "$ZSHENV")" = 1 ] && grep -q "$TMP/elsewhere/bin/shim" "$ZSHENV" && [ "$(grep -c "bin/shim:" "$ZSHRC")" = 1 ] && grep -q "$TMP/elsewhere/bin/shim" "$ZSHRC" && [ "$(grep -c "the shim line replaced" "$TMP/out")" = 2 ]' "$(cat "$ZSHENV" "$ZSHRC" "$TMP/out" "$TMP/err")"
check "and the credential helper follows it" '[ "$(envkey GIT_CONFIG_VALUE_1)" = "!$TMP/elsewhere/bin/shim/gh-credential" ]'
run >/dev/null   # back to this checkout for the cases below

echo "6. --dry-run prints the changes and writes nothing"
cp "$TMP/settings.before" "$SETTINGS"; printf 'export EDITOR=vim\n' > "$ZSHENV"; rm -f "$ZSHRC"
RC="$(run --dry-run)"
check "exit 0, the changes listed" '[ "$RC" = 0 ] && grep -q "dry run" "$TMP/out" && grep -q "^settings: .*WATCHER_APP_PROJECT" "$TMP/out" && grep -q "GH_CONFIG_DIR" "$TMP/out" && [ "$(grep -c "^profile: .*added" "$TMP/out")" = 2 ]' "$(cat "$TMP/out")"
check "nothing written" 'cmp -s "$SETTINGS" "$TMP/settings.before" && [ "$(cat "$ZSHENV")" = "export EDITOR=vim" ] && [ ! -e "$ZSHRC" ]'
check "…and the check is not run on files it did not write, and says so" 'grep -q "^check: not run: the profile changes above are not written yet" "$TMP/out"' "$(cat "$TMP/out")"

echo "7. no settings file, no profile: both made"
rm -f "$SETTINGS" "$ZSHENV" "$ZSHRC"
RC="$(run)"
check "exit 0, the settings file holds the env and nothing else" '[ "$RC" = 0 ] && [ "$(envkey WATCHER_APP_PROJECT)" = desk ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if list(d)==[\"env\"] else 1)" "$SETTINGS"' "$(cat "$SETTINGS" 2>&1)"
check "the profile is the one line" '[ "$(wc -l < "$ZSHENV" | tr -d " ")" = 1 ] && grep -q "bin/shim" "$ZSHENV"'

echo "10. card #301: ~/.zshrc prepends the directory of the real gh, and the old line sat only in ~/.zshenv"
OLD_LINE="if [ -n \"\${WATCHER_APP_PROJECT:-}\" ]; then export PATH=\"$ROOT/bin/shim:\$PATH\"; fi  # watcher card #288: a Claude session's gh is the App shim"
printf '%s\n' "$OLD_LINE" > "$ZSHENV"
printf 'export PATH="$HOME/.local/bin:$PATH"\nexport NVM_DIR="$HOME/.nvm"\n' > "$ZSHRC"
check "before: a session's shell finds the real gh — with the App named (the card's symptom) and as a snapshot shell" '[ "$(WATCHER_APP_PROJECT=desk "$FAKE_ZSH" -ic "command -v gh")" = "$HOME_DIR/.local/bin/gh" ] && [ "$(which_gh session)" = "$HOME_DIR/.local/bin/gh" ]' "$(which_gh session)"
RC="$(run)"
check "exit 0; both profiles get the new line, and ~/.zshrc keeps its own two lines above it" '[ "$RC" = 0 ] && [ "$(grep -c "the shim line" "$TMP/out")" = 2 ] && [ "$(sed -n 1p "$ZSHRC")" = "export PATH=\"\$HOME/.local/bin:\$PATH\"" ] && [ "$(wc -l < "$ZSHRC" | tr -d " ")" = 3 ] && tail -1 "$ZSHRC" | grep -q "CLAUDE_CODE_ENTRYPOINT.*$SHIM_LINE_RE"' "rc=$RC $(cat "$TMP/out" "$TMP/err" "$ZSHRC")"
check "after: a session's shell finds the shim, the owner's own terminal the real gh" '[ "$(which_gh session)" = "$ROOT/bin/shim/gh" ] && [ "$(which_gh own)" = "$HOME_DIR/.local/bin/gh" ]' "session=$(which_gh session) own=$(which_gh own)"
check "the old guard is gone from ~/.zshenv, one line there" '[ "$(grep -c "bin/shim:" "$ZSHENV")" = 1 ] && grep -q "CLAUDE_CODE_ENTRYPOINT" "$ZSHENV"' "$(cat "$ZSHENV")"

echo "11. a line the owner added to ~/.zshrc by hand, under the old guard and his own comment: replaced, not doubled"
printf 'export PATH="$HOME/.local/bin:$PATH"\nif [ -n "${WATCHER_APP_PROJECT:-}" ]; then export PATH="%s/bin/shim:$PATH"; fi  # keep the App gh shim first\n' "$ROOT" > "$ZSHRC"
RC="$(run)"
check "exit 0, one shim line, the new guard, his other line kept" '[ "$RC" = 0 ] && [ "$(grep -c "bin/shim:" "$ZSHRC")" = 1 ] && grep -q "CLAUDE_CODE_ENTRYPOINT" "$ZSHRC" && [ "$(wc -l < "$ZSHRC" | tr -d " ")" = 2 ] && grep -q "^profile: $ZSHRC: the shim line replaced" "$TMP/out"' "rc=$RC $(cat "$ZSHRC" "$TMP/out")"

echo "12. something appended to ~/.zshrc after the line (an installer): the line moves back to the end"
printf 'export PATH="$HOME/.local/bin:$PATH"  # added by an installer\n' >> "$ZSHRC"
check "before: the installer's line wins" '[ "$(which_gh session)" = "$HOME_DIR/.local/bin/gh" ]'
RC="$(run --dry-run)"
check "a dry run says it would move, writes nothing, and does not claim a check" '[ "$RC" = 0 ] && grep -q "^profile: $ZSHRC: the shim line moved to the end" "$TMP/out" && grep -q "^check: not run" "$TMP/out" && [ "$(which_gh session)" = "$HOME_DIR/.local/bin/gh" ]' "$(cat "$TMP/out")"
RC="$(run)"
check "exit 0, moved, one line, last; a session finds the shim again" '[ "$RC" = 0 ] && grep -q "the shim line moved to the end" "$TMP/out" && [ "$(grep -c "bin/shim:" "$ZSHRC")" = 1 ] && tail -1 "$ZSHRC" | grep -q "$SHIM_LINE_RE" && [ "$(which_gh session)" = "$ROOT/bin/shim/gh" ]' "rc=$RC $(cat "$ZSHRC")"
check "a comment or a blank line after it is not a reason to move it" 'printf "\n# trailing note\n" >> "$ZSHRC"; [ "$(run)" = 0 ] && grep -q "^profile: $ZSHRC: unchanged" "$TMP/out"' "$(cat "$TMP/out")"

echo "13. the shim is still not first (something after both files reorders PATH): exit 1, loudly, and it says where"
RC="$(FAKE_ZSH_LATER="$HOME_DIR/.local/bin" run)"
check "exit 1, THE SHIM IS NOT FIRST, the gh it found, and what that means" '[ "$RC" = 1 ] && grep -q "THE SHIM IS NOT FIRST" "$TMP/err" && grep -q "gh is $HOME_DIR/.local/bin/gh" "$TMP/err" && grep -q "write to GitHub as you" "$TMP/err"' "rc=$RC $(cat "$TMP/err")"
check "…and names the line that mentions that directory, without blaming it: it runs before the shim line" 'grep -q "$ZSHRC line 1 names $HOME_DIR/.local/bin" "$TMP/err" && grep -q "runs before the shim line" "$TMP/err" && grep -q "zlogin" "$TMP/err"' "$(cat "$TMP/err")"
check "a dry run with nothing left to write fails the same way: it is the state that is wrong" '[ "$(FAKE_ZSH_LATER="$HOME_DIR/.local/bin" run --dry-run)" = 1 ] && grep -q "THE SHIM IS NOT FIRST" "$TMP/err"' "$(cat "$TMP/err")"
cp "$ZSHRC" "$TMP/zshrc.good"
{ sed -n '1,2p' "$TMP/zshrc.good"; printf 'export PATH="%s/bin/shim:$PATH"\n' "$ROOT"; sed -n '3,$p' "$TMP/zshrc.good"; } > "$ZSHRC"
RC="$(run)"
check "an unguarded shim line elsewhere: exit 1, the owner's own terminal must keep its own gh" '[ "$RC" = 1 ] && grep -q "YOUR OWN TERMINAL.S gh IS THE SHIM" "$TMP/err"' "rc=$RC $(cat "$TMP/err")"
cp "$TMP/zshrc.good" "$ZSHRC"

echo "14. the real zsh, where there is one: the same two answers"
if command -v zsh >/dev/null 2>&1; then
  RC="$(env -u MAC_SETUP_ZSH ZDOTDIR="$HOME_DIR" "$SCRIPT" >"$TMP/out" 2>"$TMP/err"; echo $?)"
  check "exit 0, a session's shell finds the shim and the owner's own does not" '[ "$RC" = 0 ] && grep -q "^check: a Claude session.s shell finds $ROOT/bin/shim/gh" "$TMP/out" && grep -q "^check: your own terminal finds .*: untouched" "$TMP/out"' "rc=$RC $(cat "$TMP/out" "$TMP/err")"
else
  pass "no zsh on this machine: skipped (the stand-in covers the logic)"
fi
RC="$(MAC_SETUP_ZSH="$TMP/no-such-zsh" run)"
check "a zsh that cannot be run: exit 1, said plainly" '[ "$RC" = 1 ] && grep -q "could not ask a fresh zsh" "$TMP/err"' "rc=$RC $(cat "$TMP/err")"

echo "8. a settings file that is not JSON: exit 1, untouched, named"
printf '{"env": {\n' > "$SETTINGS"; cp "$SETTINGS" "$TMP/settings.broken"
RC="$(run)"
check "exit 1 and the file named" '[ "$RC" = 1 ] && grep -q "not valid JSON" "$TMP/err"' "rc=$RC $(cat "$TMP/err")"
check "the file is as it was" 'cmp -s "$SETTINGS" "$TMP/settings.broken"'

echo "9. a bad argument is a usage error"
RC="$(run --force)"
check "exit 2" '[ "$RC" = 2 ]'

if [ "$fail" = 0 ]; then echo "test-mac-setup.sh: $n checks, all passed"; else echo "test-mac-setup.sh: $n checks, SOME FAILED"; fi
exit $fail
