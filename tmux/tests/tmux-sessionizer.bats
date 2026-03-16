#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../tmux-sessionizer"

setup() {
  # Source the script — BASH_SOURCE guard prevents main block from running
  # shellcheck disable=SC1090
  source "$SCRIPT"
}

# ── session_name_for_path ──────────────────────────────────────────────────────

@test "session_name_for_path: plain project returns basename" {
  run session_name_for_path "/Users/x/Documents/dev/myapp"
  [ "$output" = "myapp" ]
}

@test "session_name_for_path: worktree returns parent/base" {
  run session_name_for_path "/Users/x/Documents/dev/myapp/.worktrees/feat-x"
  [ "$output" = "myapp/feat-x" ]
}

@test "session_name_for_path: dots in project name replaced with underscores" {
  run session_name_for_path "/Users/x/Documents/dev/my.app"
  [ "$output" = "my_app" ]
}

@test "session_name_for_path: worktree with dots in parent and branch" {
  run session_name_for_path "/Users/x/Documents/dev/my.app/.worktrees/v2.0"
  [ "$output" = "my_app/v2_0" ]
}

# ── tmux detection ─────────────────────────────────────────────────────────────

@test "tmux detection: does not use pgrep tmux" {
  # pgrep tmux can false-positive if any process has 'tmux' in its name.
  # The correct approach is 'tmux list-sessions 2>/dev/null'.
  run grep 'pgrep tmux' "$SCRIPT"
  [ "$status" -ne 0 ]
}
