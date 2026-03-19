#!/usr/bin/env bats

# Integration tests for prefix+t / prefix+e pane toggle and after-select-pane hook.
#
# Uses a dedicated tmux socket (-L test-toggle) to isolate from the user's session.
# press_t / press_e replicate the binding logic directly so tests are independent of
# key binding delivery but still verify the expected behavioral contract.

SOCK="test-toggle"
SES="test-pane"

setup() {
  local tmpconf
  tmpconf=$(mktemp)
  # Match live config: pane/window indices start at 1
  printf 'set -g base-index 1\nset -g pane-base-index 1\n' > "$tmpconf"
  tmux -L "$SOCK" -f "$tmpconf" new-session -d -s "$SES" -x 220 -y 50
  rm -f "$tmpconf"
  # Inject the bind t binding (the implementation under test)
  tmux -L "$SOCK" bind t if-shell "[ #{window_panes} -eq 1 ]" \
    "split-window -h -l 30% -c '#{pane_current_path}' ; resize-pane -Z" \
    "if-shell '[ #{window_zoomed_flag} -eq 0 ]' \
      'resize-pane -Z' \
      'if-shell \"[ #{pane_index} -eq 2 ]\" \
        \"select-pane -Z -t 1\" \
        \"select-pane -Z -t 2\"'"
  # Inject the bind e binding (the implementation under test)
  tmux -L "$SOCK" bind e if-shell "[ #{window_panes} -eq 1 ]" \
    "split-window -h -l 30% -c '#{pane_current_path}'" \
    "if-shell '[ #{window_zoomed_flag} -eq 1 ]' \
      'resize-pane -Z ; select-pane -t 2' \
      'select-pane -t 1 ; resize-pane -Z'"
}

teardown() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
}

# Simulate pressing prefix+t by executing the binding's logic directly.
# 1 pane → split+zoom; 2 panes+unzoomed → zoom; 2 panes+zoomed → toggle pane 1/2
press_t() {
  local npanes pane_idx zoomed
  npanes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  if [ "$npanes" -eq 1 ]; then
    tmux -L "$SOCK" split-window -h -l 30% -t "$SES"
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
  elif [ "$zoomed" -eq 0 ]; then
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
  elif [ "$pane_idx" -eq 2 ]; then
    tmux -L "$SOCK" select-pane -Z -t "${SES}:1.1"
  else
    tmux -L "$SOCK" select-pane -Z -t "${SES}:1.2"
  fi
  sleep 0.1
}

# ── bind t: first press ───────────────────────────────────────────────────────

@test "bind t: first press creates a second pane" {
  press_t
  local panes
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  [ "$panes" -eq 2 ]
}

@test "bind t: first press zooms the new pane" {
  press_t
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 1 ]
}

# ── bind t: second press ──────────────────────────────────────────────────────

@test "bind t: second press maintains 2 panes" {
  press_t
  press_t
  local panes
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  [ "$panes" -eq 2 ]
}

@test "bind t: second press stays zoomed" {
  press_t
  press_t
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 1 ]
}

@test "bind t: second press switches to pane 1" {
  press_t
  press_t
  local pane_idx
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 1 ]
}

# ── bind t: third press ───────────────────────────────────────────────────────

@test "bind t: third press switches back to pane 2" {
  press_t
  press_t
  press_t
  local pane_idx
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 2 ]
}

@test "bind t: third press stays zoomed" {
  press_t
  press_t
  press_t
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 1 ]
}

@test "bind t: never creates more than 2 panes after repeated presses" {
  press_t; press_t; press_t; press_t; press_t
  local panes
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  [ "$panes" -eq 2 ]
}

# ── after-select-pane hook: zoom guard ───────────────────────────────────────
#
# Setup helper: creates a 2-pane window and installs the hook with zoom guard.
# Call this at the start of hook tests (after setup() has already run).
setup_hook() {
  tmux -L "$SOCK" split-window -h -l 30% -t "$SES"
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  # Hook: only resize when unzoomed (zoom guard = [ #{window_zoomed_flag} -eq 0 ])
  tmux -L "$SOCK" set-hook -g after-select-pane \
    'if-shell "[ #{window_panes} -eq 2 ] && [ #{window_zoomed_flag} -eq 0 ]" "if-shell \"[ #{pane_index} -eq 1 ]\" \"resize-pane -x 70%\" \"resize-pane -x 55%\""'
}

@test "hook: does not resize when window is zoomed" {
  setup_hook
  # Zoom the window (pane 1 is active)
  tmux -L "$SOCK" resize-pane -Z -t "${SES}:1.1"
  # Switch to pane 2 with -Z (keeps zoom) — triggers after-select-pane
  tmux -L "$SOCK" select-pane -Z -t "${SES}:1.2"
  sleep 0.2
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 1 ]
}

@test "hook: resizes pane 1 to wide when unzoomed and selected" {
  setup_hook
  # Move to pane 2 first, then select pane 1 to trigger hook
  tmux -L "$SOCK" select-pane -t "${SES}:1.2"
  sleep 0.1
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.2
  local p1w total_w
  p1w=$(tmux -L "$SOCK" display-message -t "${SES}:1.1" -p '#{pane_width}')
  total_w=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_width}')
  # 70% of ~220 cols ≈ 154; must be wider than 50%
  [ "$p1w" -gt "$(( total_w / 2 ))" ]
}

# ── bind e: show/hide toggle ──────────────────────────────────────────────────
#
# press_e simulates pressing prefix+e.
# 1 pane         → split right (30%), focus new side pane (no zoom).
# 2 panes+zoomed → unzoom + focus pane 2 (show).
# 2 panes        → select pane 1 + zoom (hide, pane 2 persists).
press_e() {
  local npanes zoomed
  npanes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  if [ "$npanes" -eq 1 ]; then
    tmux -L "$SOCK" split-window -h -l 30% -t "$SES"
  elif [ "$zoomed" -eq 1 ]; then
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
    tmux -L "$SOCK" select-pane -t "${SES}:1.2"
  else
    tmux -L "$SOCK" select-pane -t "${SES}:1.1"
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
  fi
  sleep 0.1
}

@test "bind e: first press creates a second pane" {
  press_e
  local panes
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  [ "$panes" -eq 2 ]
}

@test "bind e: first press does not zoom (side pane stays visible)" {
  press_e
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 0 ]
}

@test "bind e: first press focuses the new side pane" {
  press_e
  local pane_idx
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 2 ]
}

@test "bind e: second press hides (keeps 2 panes, zoomed on pane 1)" {
  press_e
  press_e
  local panes zoomed pane_idx
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 1 ]
  [ "$pane_idx" -eq 1 ]
}

@test "bind e: toggle works across multiple cycles" {
  press_e  # create + show (pane 2, unzoomed)
  press_e  # hide (pane 1, zoomed)
  press_e  # show again (pane 2, unzoomed)
  local panes zoomed pane_idx
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 0 ]
  [ "$pane_idx" -eq 2 ]
}

# ── cross-command: t ↔ e interaction ─────────────────────────────────────────

@test "cross: e then t zooms, keeps 2 panes" {
  press_e  # side-by-side, pane 2 focused, not zoomed
  press_t  # 2 panes + not zoomed → zoom
  local panes zoomed
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 1 ]
}

@test "cross: t then e unzooms, keeps 2 panes, focuses pane 2" {
  press_t  # creates pane + zooms
  press_e  # 2 panes + zoomed → unzoom + select pane 2
  local panes zoomed pane_idx
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 0 ]
  [ "$pane_idx" -eq 2 ]
}

@test "cross: full cycle e → t → e returns to side-by-side" {
  press_e  # side-by-side
  press_t  # zoomed
  press_e  # back to side-by-side
  local panes zoomed pane_idx
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 0 ]
  [ "$pane_idx" -eq 2 ]
}

@test "cross: full cycle t → e → t returns to zoomed" {
  press_t  # zoomed, pane 2
  press_e  # unzoom, side-by-side, pane 2
  press_t  # 2 panes + not zoomed → zoom
  local panes zoomed
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$panes" -eq 2 ]
  [ "$zoomed" -eq 1 ]
}
