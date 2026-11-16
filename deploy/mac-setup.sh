#!/usr/bin/env bash
#
# deploy/mac-setup.sh [--dry-run]   (card #288)
#
# Points the owner's Claude sessions on this Mac at the desk App, roloc-desk-author, so every
# write one of them makes on GitHub — a comment, a card move, a commit, a PR — is signed by that
# App: never the owner's own login (`roloc` is his hand alone), never a lane's App, never a
# machine account. Run as yourself, on the Mac, after
#
#   python3 deploy/app-setup.py desk --all-repos
#
# has written the App's key under ~/.config/roloc-apps/desk/. Idempotent: run it again any time;
# it says "unchanged" for what is already in place. --dry-run prints every change and writes
# nothing. Never run by a tick, never on the box.
#
# What it writes:
#   ~/.claude/settings.json, its "env" (every other key is kept):
#     WATCHER_APP_PROJECT=desk        bin/gh-app-token.sh mints the desk App whatever checkout the
#                                     session is in; without it the git remote would pick that
#                                     project's lane App, so a session in the riffmap checkout
#                                     would write as roloc-riffmap-author
#     GIT_AUTHOR_*, GIT_COMMITTER_*   the App's identity, from `bin/gh-app-token.sh desk author --identity`
#     GIT_CONFIG_COUNT, _KEY_n, _VALUE_n   credential.helper emptied, then bin/shim/gh-credential
#     GH_CONFIG_DIR                   removed: it named the suspended roloc-desk login
#   ~/.zshenv and ~/.zshrc: one guarded line in each that puts bin/shim first on PATH in a
#     Claude session's shell and nowhere else — a session's `gh` is the shim, the owner's own
#     terminal `gh` is untouched. Card #301 (November 16, 2026: a session commented, merged and
#     relabeled as `roloc` while its `git push` went out as the App) is why it is shaped so:
#       - Both files, and LAST in ~/.zshrc: ~/.zshrc runs after ~/.zshenv, so one that prepends
#         ~/.local/bin (the real gh) or loads nvm puts them ahead of a line that lives only in
#         ~/.zshenv.
#       - The guard is WATCHER_APP_PROJECT, CLAUDE_CODE_ENTRYPOINT or CLAUDECODE, any one set.
#         Claude Code sources these files ONCE, when a session starts, to build a shell
#         snapshot that ends in a fixed `export PATH=…`; every Bash command then starts from
#         that snapshot. WATCHER_APP_PROJECT (from the settings file's "env") is in a command's
#         environment but not yet in the snapshot shell's, so a guard on it alone never fired:
#         all five snapshots on the owner's Mac, October 29 to November 16, had no bin/shim on
#         PATH. The desktop app starts a session's process with CLAUDE_CODE_ENTRYPOINT set, so
#         the snapshot shell has it. With the shim first and no WATCHER_APP_PROJECT the shim
#         passes straight through to the real gh, so a guard that fires too often costs nothing.
#       - A line from before this shape (the first guard, or one added by hand) is replaced.
#
# Then it checks the result, not the files, by asking a fresh `zsh -ic 'command -v gh'` twice:
#   as a session's snapshot shell is started (CLAUDE_CODE_ENTRYPOINT set, WATCHER_APP_PROJECT
#     not): it must find bin/shim/gh;
#   as the owner's own terminal is (none of the three set): it must NOT find the shim.
# If either is wrong the script exits 1 and, for the first, names the file and line that put the
# other gh's directory ahead. A dry run with profile changes still to write does not check (the
# answer would be about files it did not write).
#
# Test seams: MAC_SETUP_SETTINGS (the settings file), MAC_SETUP_ZSHENV and MAC_SETUP_ZSHRC (the
# profiles; default under ${ZDOTDIR:-$HOME}), MAC_SETUP_ZSH (the zsh the check runs; default the
# one on PATH), HOME (where ~/.config/roloc-apps/desk/ is looked for), WATCHER_HOME (the
# checkout; default: this script's parent).
set -euo pipefail

dry=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    *) echo "usage: deploy/mac-setup.sh [--dry-run]" >&2; exit 2 ;;
  esac
done

WATCHER_HOME="${WATCHER_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SETTINGS="${MAC_SETUP_SETTINGS:-$HOME/.claude/settings.json}"
ZSHENV="${MAC_SETUP_ZSHENV:-${ZDOTDIR:-$HOME}/.zshenv}"
ZSHRC="${MAC_SETUP_ZSHRC:-${ZDOTDIR:-$HOME}/.zshrc}"
TOKEN="$WATCHER_HOME/bin/gh-app-token.sh"
[ -x "$TOKEN" ] || { echo "mac-setup: $TOKEN is missing; WATCHER_HOME must be the watcher checkout" >&2; exit 1; }

# The App's identity is the proof it is set up: the token script reads only the config for it.
if ! identity="$(GH_APP_DIR= WATCHER_APP_PROJECT=desk "$TOKEN" desk author --identity 2>&1)"; then
  echo "mac-setup: the desk App is not set up on this Mac ($identity)" >&2
  echo "  first: python3 $WATCHER_HOME/deploy/app-setup.py desk --all-repos" >&2
  exit 1
fi
name="${identity%% <*}"
email="${identity#*<}"; email="${email%>}"

[ "$dry" = 1 ] && echo "mac-setup: dry run, writing nothing"
echo "mac-setup: the desk App is $name"

# The settings file and the profile are edited by Python: a JSON merge that keeps every other
# key, and one marked line in the profile replaced or appended, each written whole and atomically.
MAC_SETUP_NAME="$name" MAC_SETUP_EMAIL="$email" MAC_SETUP_HOME="$WATCHER_HOME" MAC_SETUP_DRY="$dry" \
MAC_SETUP_SETTINGS="$SETTINGS" MAC_SETUP_ZSHENV="$ZSHENV" MAC_SETUP_ZSHRC="$ZSHRC" python3 - <<'PY'
import json, os, re, shutil, subprocess, sys

settings, zshenv = os.environ["MAC_SETUP_SETTINGS"], os.environ["MAC_SETUP_ZSHENV"]
zshrc = os.environ["MAC_SETUP_ZSHRC"]
home, dry = os.environ["MAC_SETUP_HOME"], os.environ["MAC_SETUP_DRY"] == "1"
name, email = os.environ["MAC_SETUP_NAME"], os.environ["MAC_SETUP_EMAIL"]


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


# -- settings.json: the env keys a session needs, nothing else touched
try:
    with open(settings) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("not an object")
except FileNotFoundError:
    data = {}
except ValueError as e:
    sys.exit(f"mac-setup: {settings} is not valid JSON ({e}); fix it by hand, nothing written")
env = data.get("env")
if not isinstance(env, dict):
    env = {}
want = {
    "WATCHER_APP_PROJECT": "desk",
    "GIT_AUTHOR_NAME": name, "GIT_AUTHOR_EMAIL": email,
    "GIT_COMMITTER_NAME": name, "GIT_COMMITTER_EMAIL": email,
    "GIT_CONFIG_COUNT": "2",
    "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
    "GIT_CONFIG_KEY_1": "credential.helper", "GIT_CONFIG_VALUE_1": f"!{home}/bin/shim/gh-credential",
}
changes = [k for k, v in want.items() if env.get(k) != v]
if "GH_CONFIG_DIR" in env:
    changes.append("-GH_CONFIG_DIR")
if changes:
    new_env = {k: v for k, v in env.items() if k != "GH_CONFIG_DIR"}
    new_env.update(want)
    data["env"] = new_env
    print(f"settings: {settings}: " + ", ".join(changes))
    if not dry:
        write(settings, json.dumps(data, indent=2) + "\n")
else:
    print(f"settings: {settings}: unchanged")

# -- .zshenv and .zshrc: the shim first on PATH, only for a session that names an App
marker = "# watcher card #288: a Claude session's gh is the App shim"
GUARD = ("WATCHER_APP_PROJECT", "CLAUDE_CODE_ENTRYPOINT", "CLAUDECODE")
stmt = 'if [ -n "' + "".join("${%s:-}" % v for v in GUARD) + f'" ]; then export PATH="{home}/bin/shim:$PATH"; fi'
line = f"{stmt}  {marker}"
# The statement under any guard and for any checkout, with any comment or none: the first
# shape (WATCHER_APP_PROJECT alone), a line the owner added by hand, one that names a checkout
# that has since moved. Exactly `stmt` is the line; anything else this matches is replaced.
shape = re.compile(r'^\s*if \[ -n "(?:\$\{[A-Z_]+:-\})+" \]; then export PATH="(.+)/bin/shim:\$PATH"; fi\s*(#.*)?$')


def profile(path, last):
    """One shim line in `path`. `last`: it must be the file's last line that does anything
    (.zshrc — whatever follows it can prepend to PATH again). Returns True on a change."""
    try:
        with open(path) as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        lines = [""]
    have = [i for i, l in enumerate(lines) if marker in l or shape.match(l)]
    here = len(have) == 1 and lines[have[0]].split("  #")[0].strip() == stmt
    after = [l for l in lines[have[0] + 1:] if l.strip() and not l.strip().startswith("#")] if have else []
    if here and not (last and after):
        print(f"profile: {path}: unchanged")
        return False
    kept = [l for i, l in enumerate(lines) if i not in have]
    if kept and kept[-1] == "":
        kept.pop()
    kept.append(line)
    what = "the shim line moved to the end" if here else "the shim line replaced" if have else "the shim line added"
    print(f"profile: {path}: {what}")
    if not dry:
        write(path, "\n".join(kept) + "\n")
    return True


pending = [profile(zshenv, last=False), profile(zshrc, last=True)]

# -- the check: which gh does a fresh session's shell find? The files can both be right and
# the answer still wrong (a file ~/.zshrc sources, a ZDOTDIR), so ask the shell.
shim = os.path.join(home, "bin", "shim", "gh")
zsh = os.environ.get("MAC_SETUP_ZSH") or shutil.which("zsh")


def culprit(found):
    """The first line, after the shim line, of either profile that names the directory the
    wrong gh is in — spelled out, or with $HOME, ${HOME} or ~."""
    d = os.path.dirname(found)
    h = os.environ.get("HOME", "")
    names = {d}
    if h and (d == h or d.startswith(h + "/")):
        names |= {"$HOME" + d[len(h):], "${HOME}" + d[len(h):], "~" + d[len(h):]}
    for path in (zshrc, zshenv):
        try:
            with open(path) as f:
                lines = f.read().split("\n")
        except OSError:
            continue
        start = max([i for i, l in enumerate(lines) if shape.match(l)] or [-1])
        for i in list(range(start + 1, len(lines))) + list(range(0, max(start, 0))):
            if any(n in lines[i] for n in names) and not lines[i].strip().startswith("#"):
                return f"{path} line {i + 1} puts {d} on PATH: {lines[i].strip()}"
    return None


def which_gh(session):
    """What `command -v gh` prints in a fresh interactive zsh, started the way a session's
    snapshot shell is (`session`) or the way the owner's own terminal is."""
    env = {k: v for k, v in os.environ.items() if k not in GUARD}
    if session:
        env["CLAUDE_CODE_ENTRYPOINT"] = "claude-desktop"
    try:
        r = subprocess.run([zsh, "-ic", "command -v gh"], env=env, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        sys.exit(f"mac-setup: could not ask a fresh zsh which gh it finds ({e})")
    out = [l.strip() for l in r.stdout.split("\n") if l.strip()]
    return out[-1] if out else ""


def is_shim(found):
    try:
        return bool(found) and os.path.samefile(found, shim)
    except OSError:
        return False


if dry and any(pending):
    print("check: not run: the profile changes above are not written yet")
elif not zsh:
    print("check: not run: no zsh on this machine")
else:
    found, own = which_gh(session=True), which_gh(session=False)
    if not is_shim(found):
        why = culprit(found) if found else None
        sys.exit(
            f"mac-setup: THE SHIM IS NOT FIRST. A fresh Claude session's gh is {found or 'not found at all'},\n"
            f"  not {shim} — so a session would write to GitHub as you, not as the App.\n"
            + (f"  {why}\n" if why else f"  Neither {zshrc} nor {zshenv} names that directory after the shim line;\n"
                                        "  look at what they source (nvm, a plugin manager) and at ZDOTDIR.\n")
            + "  The shim line has to be the last thing a session's shell runs that changes PATH."
        )
    if is_shim(own):
        sys.exit(
            f"mac-setup: YOUR OWN TERMINAL'S gh IS THE SHIM ({own}). It should be your own gh:\n"
            f"  something other than the guarded line puts {os.path.dirname(shim)} on PATH. Look in {zshrc} and {zshenv}."
        )
    print(f"check: a Claude session's shell finds {found}: the shim is first")
    print(f"check: your own terminal finds {own or 'no gh'}: untouched")
PY

if [ "$dry" = 1 ]; then
  echo "mac-setup: dry run done; nothing written"
else
  echo "mac-setup: done. A Claude session started from now on writes to GitHub as $name;"
  echo "  the one you are in keeps its old environment until it is restarted. Your own terminal's gh is unchanged."
fi
