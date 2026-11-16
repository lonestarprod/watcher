# NullTrader #131 (November 16, 2026): the build lane's tick routed a card to the design
# lane ("your A is a new map look, so I routed this card to the game designer … the designer
# draws the whole-galaxy layout and posts it here"). A minute later the design lane's own
# tick was launched for it, read that comment, took itself for the build lane and ended in
# five seconds and two turns: "Card #131 is not mine to work. Its label is `agent:
# game-designer`, so the design lane owns it. … I changed nothing and did not claim it." The
# next poll did the same. Two clean exits with the card still In progress under the lane's
# own label is two no-progress attempts, so the spawner parked the card and asked the owner
# what should happen to it. NullTrader #58 went the same way on November 2, 2026.
#
# Nothing a tick read said which lane it was: the launch line is the same for every lane,
# and commands/watch.md §1 called the number "the owner named one here". Now §1 says a
# number there is the spawner handing over the card and that it is this tick's, bin/spawn.sh
# exports the lane (WATCHER_LANE, WATCHER_LANE_AGENTS), and mods/card-context puts it under
# the card's title in the system prompt.
#
# This seeds that hand-off: a card labeled `agent: designer`, In progress, Stage Waiting,
# whose newest comment is the build tick's routing FYI in watch.md §2's own words, run as the
# design lane (CASE_LANE). The right tick claims the card and says something on it. What it
# then writes is not this case's business — the brief is small so the tick can finish, but
# the checks stop at "it took the card and did not hand it away". Whether this is a
# sensitivity proof or a regression guard is for the deployer's first runs to say
# (bin/eval.sh's header); it could not be run from the Mac that wrote it.

case_setup() {
  local fx="$TMP/fixture"
  mkdir -p "$fx/.claude/agents" "$fx/docs/design"
  cat > "$fx/CLAUDE.md" <<'EOF'
# fixture project

A tiny fixture repo for the watcher's replay suite (card #34/#43). Not a real project.

- The required CI check is `verify`.
- Two lanes. The build lane takes `agent: builder`; the design lane takes `agent: designer`
  (`.claude/agents/designer.md`).
- A design card's deliverable is one short brief, `docs/design/<slug>.md`: the wording or
  layout chosen, and one sentence of why. It ships as a docs-only PR (no review), and the
  card closes with it. Nothing under `docs/design/` needs the owner's approval first.
- No contracts, no spend receipts, no screens: nothing here renders.
EOF
  cat > "$fx/.claude/agents/designer.md" <<'EOF'
---
name: designer
description: How something reads or looks — wording, layout, a brief under docs/design/.
---

You write the brief the card asks for, under `docs/design/`, and ship it as a docs-only PR.
EOF
  printf '# Design briefs\n\nOne file per decision.\n' > "$fx/docs/design/README.md"
  seed_repo "$fx"
  new_worktree "card-$ISSUE" main

  seed_card "$ISSUE" "The empty inbox says nothing — what should it say?" "In progress" "P1" <<'EOF'
**Ask: pick the words the inbox shows when it is empty.**

Today an empty inbox is a blank panel, and people think it failed to load. Show me the
wording you would use and write it down as a brief; I do not need options, just your pick
and one sentence of why.

## Done when

- `docs/design/empty-inbox.md` holds the wording and the reason.
EOF
  python3 - "$FAKEHUB_STATE" <<'PY'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d["labels"] = ["agent: builder", "agent: designer", "in-flight", "blocked"]
it = d["issues"]["100"]
it["labels"] = ["agent: designer"]
it["stage"] = "Waiting"
it["comments"] = [
    "🤖 Watcher picked this up at 2026-11-16T17:04:30Z.",
    "🤖 FYI: this reads as design work, so I routed it to the designer.\n"
    "- The design lane picks it up on its next poll, within a minute.\n"
    "- Nothing for the owner to do.",
]
json.dump(d, open(path, "w"))
PY

  CASE_LANE="fixture-design"
  CASE_LANE_AGENTS="designer"
  CASE_COMMAND="/watch $ISSUE"
}

case_check() {
  # The symptom: the tick left without ever taking the card. The claim is the label going on
  # (watch.md §1), whatever became of it by the end.
  if grep -qE 'gh issue edit 100 .*--add-label in-flight' "$EVAL_LOG"; then
    pass "routed-card: the tick claimed the card"
  else
    flunk "routed-card: the tick never claimed the card" "no 'gh issue edit 100 --add-label in-flight' in the call log"
  fi

  # Two comments are seeded. A tick that worked the card said something: the pickup line, a
  # plan, a brief's PR.
  local comments
  comments="$(python3 - "$FAKEHUB_STATE" <<'PY'
import json, sys
print(len(json.load(open(sys.argv[1]))["issues"]["100"]["comments"]))
PY
)"
  if [ "${comments:-0}" -gt 2 ]; then
    pass "routed-card: the tick said something on the card"
  else
    flunk "routed-card: the tick said nothing on the card" "${comments:-0} comment(s), 2 seeded"
  fi

  # Its own report must not hand the card to a lane that is itself.
  local said
  said="$(result_field result | tr '\n' ' ')"
  if printf '%s' "$said" | grep -qiE "(not|isn.t) mine( to (work|build|touch))?|did not claim|didn.t claim|the design lane (owns|picks|takes|will)"; then
    flunk "routed-card: the tick disowned the card" "$(printf '%s' "$said" | cut -c1-200)"
  else
    pass "routed-card: the tick's report does not disown the card"
  fi

  # And it stayed the design lane's: no relabel back to the builder or anywhere else.
  if state issues.100.labels | grep -qx 'agent: designer' \
     && [ "$(state issues.100.labels | grep -c '^agent: ')" = 1 ]; then
    pass "routed-card: still labeled agent: designer"
  else
    flunk "routed-card: the card was relabeled away from the design lane" "labels: $(state issues.100.labels | tr '\n' ',')"
  fi
}
