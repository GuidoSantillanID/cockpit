#!/usr/bin/env bats

TMUX_CONF="$BATS_TEST_DIRNAME/../tmux.conf"

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
