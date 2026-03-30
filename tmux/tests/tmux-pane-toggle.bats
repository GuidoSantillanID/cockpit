#!/usr/bin/env bats

# Integration tests for prefix+t / prefix+e pane toggle and after-select-pane hook.
#
# Uses a dedicated tmux socket (-L test-toggle) to isolate from the user's session.
# press_t / press_e replicate the binding logic directly so tests are independent of
# key binding delivery but still verify the expected behavioral contract.

SOCK="test-toggle"
SES="test-pane"
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT="$SCRIPT_DIR/../tmux-pane-focus"

pane_focus() {
  TMUX_PANE_FOCUS_SOCK="$SOCK" TMUX_PANE_FOCUS_TARGET="$SES" "$SCRIPT" "$@"
}

setup() {
  local tmpconf
  tmpconf=$(mktemp)
  # Match live config: pane/window indices start at 1
  printf 'set -g base-index 1\nset -g pane-base-index 1\n' > "$tmpconf"
  tmux -L "$SOCK" -f "$tmpconf" new-session -d -s "$SES" -x 220 -y 50
  rm -f "$tmpconf"
}

teardown() {
  tmux -L "$SOCK" kill-server 2>/dev/null || true
}

# Simulate pressing prefix+t via inline tmux logic (matches live tmux.conf binding).
press_t() {
  local npanes zoomed pane_idx
  npanes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  if [ "$npanes" -eq 1 ]; then
    tmux -L "$SOCK" split-window -h -l 30% -t "$SES"
    local new_id
    new_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
    tmux -L "$SOCK" set -w -t "$SES" @secondary "$new_id"
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
  elif [ "$zoomed" -eq 0 ]; then
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
  elif [ "$pane_idx" -eq 1 ]; then
    local sec
    sec=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
    tmux -L "$SOCK" select-pane -Z -t "$sec"
  else
    tmux -L "$SOCK" select-pane -Z -t "${SES}:1.1"
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
# Simulate pressing prefix+e via inline tmux logic (matches live tmux.conf binding).
press_e() {
  local npanes zoomed
  npanes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  if [ "$npanes" -eq 1 ]; then
    tmux -L "$SOCK" split-window -h -l 30% -t "$SES"
    local new_id
    new_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
    tmux -L "$SOCK" set -w -t "$SES" @secondary "$new_id"
  elif [ "$zoomed" -eq 1 ]; then
    tmux -L "$SOCK" resize-pane -Z -t "$SES"
    local sec
    sec=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
    tmux -L "$SOCK" select-pane -t "$sec"
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

# ── tmux-pane-focus script tests ─────────────────────────────────────────────

@test "track: sets @secondary when non-main pane is focused" {
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.1
  # Pane 2 is now focused; run track
  pane_focus track
  local secondary
  secondary=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  [ -n "$secondary" ]
  # Verify it points to pane 2's ID
  local pane2_id
  pane2_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ "$secondary" = "$pane2_id" ]
}

@test "track: does not set @secondary when pane 1 is focused" {
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.1
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.1
  pane_focus track
  local secondary
  secondary=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  [ -z "$secondary" ]
}

@test "track: get_secondary falls back to last pane when @secondary is unset" {
  tmux -L "$SOCK" split-window -h -t "$SES"
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.1
  # Focus pane 1 (so @secondary stays unset from track)
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.1
  # get_secondary should fall back to the highest-index pane
  local expected
  expected=$(tmux -L "$SOCK" list-panes -t "$SES" -F '#{pane_id}' | tail -1)
  local actual
  actual=$(pane_focus _get_secondary)
  [ "$actual" = "$expected" ]
}

# ── multi-pane: 3+ pane scenarios ────────────────────────────────────────────

# Helper: create a 3-pane window (pane 1 = main, pane 2, pane 3)
setup_3_panes() {
  tmux -L "$SOCK" split-window -h -t "$SES"
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.1
  # Track pane 3 as secondary (it's currently focused after second split)
  pane_focus track
}

@test "multi: track updates @secondary when switching between extra panes" {
  setup_3_panes
  # @secondary should be pane 3 (last split, focused)
  local sec_after_3
  sec_after_3=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  local pane3_id
  pane3_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ "$sec_after_3" = "$pane3_id" ]

  # Switch to pane 2, track again
  tmux -L "$SOCK" select-pane -t "${SES}:1.2"
  sleep 0.1
  pane_focus track
  local sec_after_2
  sec_after_2=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  local pane2_id
  pane2_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ "$sec_after_2" = "$pane2_id" ]
}

@test "multi: zoom toggles between main and @secondary with 3 panes" {
  setup_3_panes
  # Pane 3 is focused and tracked as @secondary
  # press_t: unzoomed → zoom current (pane 3)
  press_t
  local zoomed pane_idx
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$zoomed" -eq 1 ]
  [ "$pane_idx" -eq 3 ]

  # press_t: zoomed on pane 3 (not pane 1) → switch to pane 1, stay zoomed
  press_t
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$zoomed" -eq 1 ]
  [ "$pane_idx" -eq 1 ]

  # press_t: zoomed on pane 1 → switch to @secondary (pane 3), stay zoomed
  press_t
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$zoomed" -eq 1 ]
  [ "$pane_idx" -eq 3 ]
}

@test "multi: side toggle unzooms to @secondary with 3 panes" {
  setup_3_panes
  # Zoom pane 3 first
  press_t
  local zoomed
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 1 ]

  # press_e: zoomed → unzoom, focus @secondary (pane 3)
  press_e
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  local pane_idx
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$zoomed" -eq 0 ]
  [ "$pane_idx" -eq 3 ]

  # press_e: unzoomed → select pane 1, zoom (hide all)
  press_e
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$zoomed" -eq 1 ]
  [ "$pane_idx" -eq 1 ]
}

@test "multi: changing @secondary changes zoom toggle target" {
  setup_3_panes
  # @secondary = pane 3 (from setup)
  # Switch to pane 2 and track it
  tmux -L "$SOCK" select-pane -t "${SES}:1.2"
  sleep 0.1
  pane_focus track

  # Now zoom: unzoomed → zoom current (pane 2)
  press_t
  local pane_idx
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 2 ]

  # Toggle: zoomed on pane 2 (not pane 1) → go to pane 1
  press_t
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 1 ]

  # Toggle: zoomed on pane 1 → go to @secondary (pane 2, not pane 3)
  press_t
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  [ "$pane_idx" -eq 2 ]
}

# ── dead-pane fallback (script-level) ────────────────────────────────────────

@test "script: get_secondary falls back when @secondary pane is killed" {
  setup_3_panes
  # @secondary = pane 3
  local pane3_id
  pane3_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  # Kill pane 3
  tmux -L "$SOCK" kill-pane -t "$pane3_id"
  sleep 0.1
  # get_secondary should fall back to the last surviving pane (pane 2)
  local expected
  expected=$(tmux -L "$SOCK" list-panes -t "$SES" -F '#{pane_id}' | tail -1)
  local actual
  actual=$(pane_focus _get_secondary)
  [ "$actual" = "$expected" ]
}

@test "script: side unzooms to fallback when @secondary is dead" {
  setup_3_panes
  local pane3_id
  pane3_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  # Zoom pane 3, then kill it while zoomed on pane 1
  pane_focus zoom   # zoom pane 3
  sleep 0.1
  pane_focus zoom   # toggle to pane 1 (stay zoomed)
  sleep 0.1
  tmux -L "$SOCK" resize-pane -Z -t "$SES"  # unzoom to kill safely
  sleep 0.1
  tmux -L "$SOCK" kill-pane -t "$pane3_id"
  sleep 0.1
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.1
  tmux -L "$SOCK" resize-pane -Z -t "$SES"  # zoom pane 1
  sleep 0.1
  # side: zoomed → unzoom + select @secondary (dead) → fallback to pane 2
  pane_focus side
  sleep 0.1
  local pane_idx zoomed
  pane_idx=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_index}')
  zoomed=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_zoomed_flag}')
  [ "$zoomed" -eq 0 ]
  [ "$pane_idx" -eq 2 ]
}

# ── hook integration ─────────────────────────────────────────────────────────
#
# Install the live after-select-pane hook (conditional format tracking) and
# verify @secondary updates without explicit pane_focus track calls.

setup_with_hooks() {
  # Use the script for tracking (matches production behavior, handles pane_index check)
  tmux -L "$SOCK" set-hook -g after-split-window \
    "run-shell 'TMUX_PANE_FOCUS_SOCK=$SOCK TMUX_PANE_FOCUS_TARGET=$SES $SCRIPT track'"
  tmux -L "$SOCK" set-hook -g after-select-pane \
    "run-shell 'TMUX_PANE_FOCUS_SOCK=$SOCK TMUX_PANE_FOCUS_TARGET=$SES $SCRIPT track'"
}

@test "hook: after-split-window sets @secondary on new pane" {
  setup_with_hooks
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.3
  local secondary pane2_id
  secondary=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  pane2_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ -n "$secondary" ]
  [ "$secondary" = "$pane2_id" ]
}

@test "hook: after-select-pane updates @secondary on pane switch" {
  setup_with_hooks
  tmux -L "$SOCK" split-window -h -t "$SES"
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.3
  # Pane 3 focused after second split — hook should have set @secondary
  local sec_pane3
  sec_pane3=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  local pane3_id
  pane3_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ "$sec_pane3" = "$pane3_id" ]

  # Switch to pane 2 — hook should update @secondary
  tmux -L "$SOCK" select-pane -t "${SES}:1.2"
  sleep 0.3
  local sec_pane2
  sec_pane2=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  local pane2_id
  pane2_id=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_id}')
  [ "$sec_pane2" = "$pane2_id" ]
}

@test "hook: after-select-pane does not update @secondary on pane 1" {
  setup_with_hooks
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.3
  # @secondary set to pane 2 by split hook
  local sec_before
  sec_before=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  # Switch to pane 1
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.3
  local sec_after
  sec_after=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{@secondary}')
  # @secondary should be unchanged (still pane 2)
  [ "$sec_after" = "$sec_before" ]
}

# ── path with spaces ─────────────────────────────────────────────────────────

@test "script: side handles path with spaces" {
  # Create a directory with spaces; resolve symlinks (macOS: /tmp → /private/tmp)
  local spacedir
  spacedir=$(realpath "$(mktemp -d "/tmp/pane_focus_space_test_XXXX")")
  mkdir -p "$spacedir/sub dir"
  # respawn-pane sets pane_current_path directly (send-keys cd doesn't in test shells)
  tmux -L "$SOCK" respawn-pane -t "$SES" -k -c "$spacedir/sub dir"
  sleep 0.3
  # side from 1 pane should split into the space-containing path
  pane_focus side
  sleep 0.3
  local panes new_path
  panes=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{window_panes}')
  new_path=$(tmux -L "$SOCK" display-message -t "$SES" -p '#{pane_current_path}')
  [ "$panes" -eq 2 ]
  [ "$new_path" = "$spacedir/sub dir" ]
  rm -rf "$spacedir"
}
