#!/usr/bin/env bats

TMUX_CONF="$BATS_TEST_DIRNAME/../tmux.conf"
SETTINGS_JSON="$BATS_TEST_DIRNAME/../../claude/settings.json"

# ── Tab indicator: @is_claude_running should NOT produce a dot ─────────────────
# The robot-icon window name already signals Claude is running — the peach dot
# is redundant. Only the green dot (@claude_done) should be shown.

@test "active tab format: does not reference @is_claude_running" {
  local fmt
  fmt=$(grep 'window-status-current-format' "$TMUX_CONF")
  ! echo "$fmt" | grep -q '@is_claude_running'
}

@test "inactive tab format: does not reference @is_claude_running" {
  local fmt
  fmt=$(grep 'window-status-format' "$TMUX_CONF" | grep -v 'current')
  ! echo "$fmt" | grep -q '@is_claude_running'
}

# ── Tab indicator: @claude_done must still show a green dot ───────────────────

@test "active tab format: shows green dot for @claude_done" {
  local fmt
  fmt=$(grep 'window-status-current-format' "$TMUX_CONF")
  echo "$fmt" | grep -q '@claude_done.*thm_green'
}

@test "inactive tab format: shows green dot for @claude_done" {
  local fmt
  fmt=$(grep 'window-status-format' "$TMUX_CONF" | grep -v 'current')
  echo "$fmt" | grep -q '@claude_done.*thm_green'
}

# ── settings.json hooks: must target $TMUX_PANE, not the active window ────────
# Without -t "$TMUX_PANE", set-option -w targets whichever window the user is
# currently viewing when the hook fires, not the window where Claude ran.

@test "hooks: every @claude_done set-option targets TMUX_PANE" {
  # All occurrences of the claude_done command must include -t "$TMUX_PANE".
  # Without it, set-option -w targets the active window, not the one Claude ran in.
  local total targeted
  total=$(grep -c 'claude_done' "$SETTINGS_JSON")
  targeted=$(grep 'claude_done' "$SETTINGS_JSON" | grep -c 'TMUX_PANE')
  [ "$total" -gt 0 ]
  [ "$total" -eq "$targeted" ]
}
