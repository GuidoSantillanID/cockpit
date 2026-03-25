#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../shell-functions.zsh"

setup() {
  MOCK_DIR=$(mktemp -d)
  CALL_LOG="$MOCK_DIR/calls.log"
  MOCK_TARGET="$MOCK_DIR/target"
  mkdir -p "$MOCK_TARGET"

  # Mock 'claude' binary — used by 'command claude' inside the claude() wrapper
  printf '#!/usr/bin/env bash\necho "claude %s" >> "%s"\n' '"$*"' "$CALL_LOG" > "$MOCK_DIR/claude"
  chmod +x "$MOCK_DIR/claude"

  # Mock 'wt' binary — outputs MOCK_TARGET so the wrapper can cd to it
  printf '#!/usr/bin/env bash\necho "%s"\n' "$MOCK_TARGET" > "$MOCK_DIR/wt"
  chmod +x "$MOCK_DIR/wt"

  export MOCK_DIR CALL_LOG MOCK_TARGET
  export PATH="$MOCK_DIR:$PATH"

  # shellcheck disable=SC1090
  source "$SCRIPT"
}

teardown() {
  rm -rf "$MOCK_DIR"
}

# ── claude() wrapper — tmux integration ───────────────────────────────────────

setup_tmux_mock() {
  tmux() {
    echo "tmux $*" >> "$CALL_LOG"
    case "$*" in
      "display-message -p #W") echo "original-window" ;;
    esac
  }
  export -f tmux
}

@test "claude: renames window to '󰚩 claude' inside tmux" {
  setup_tmux_mock
  export TMUX="fake-tmux-session"
  claude --version
  grep -q "rename-window 󰚩 claude" "$CALL_LOG"
}

@test "claude: sets @is_claude_running when starting" {
  setup_tmux_mock
  export TMUX="fake-tmux-session"
  claude --version
  grep -q "set-option -w @is_claude_running 1" "$CALL_LOG"
}

@test "claude: does NOT set @claude_done on exit" {
  setup_tmux_mock
  export TMUX="fake-tmux-session"
  claude --version
  ! grep -q "set-option -w @claude_done 1" "$CALL_LOG"
}

@test "claude: unsets @is_claude_running on exit" {
  setup_tmux_mock
  export TMUX="fake-tmux-session"
  claude --version
  grep -q "set-option -wu @is_claude_running" "$CALL_LOG"
}

@test "claude: re-enables automatic-rename on exit" {
  setup_tmux_mock
  export TMUX="fake-tmux-session"
  claude --version
  grep -q "set-option -wu automatic-rename" "$CALL_LOG"
}

@test "claude: falls through to command claude outside tmux" {
  tmux() { echo "tmux $*" >> "$CALL_LOG"; }
  export -f tmux
  unset TMUX
  claude --version
  # tmux should NOT have been called
  ! grep -q "^tmux" "$CALL_LOG" 2>/dev/null
}

# ── wt() wrapper — cd behavior ────────────────────────────────────────────────

@test "wt new: cds to directory printed by command wt" {
  local orig_dir="$PWD"
  wt new my-feature
  [ "$PWD" = "$MOCK_TARGET" ]
}

@test "wt finish: cds to directory printed by command wt" {
  local orig_dir="$PWD"
  wt finish
  [ "$PWD" = "$MOCK_TARGET" ]
}

@test "wt list: passes through without cd" {
  local orig_dir="$PWD"
  wt list
  [ "$PWD" = "$orig_dir" ]
}

@test "wt done: passes through without cd" {
  local orig_dir="$PWD"
  wt done
  [ "$PWD" = "$orig_dir" ]
}
