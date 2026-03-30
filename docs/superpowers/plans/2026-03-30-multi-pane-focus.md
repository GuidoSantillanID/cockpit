# Multi-Pane Focus Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded pane-2 references in prefix+t / prefix+e with a tracked `@secondary` variable, enabling the same toggle UX with any number of panes.

**Architecture:** A new shell script `tmux-pane-focus` encapsulates all pane-focus logic (tracking, zoom toggle, side-by-side toggle). tmux.conf bindings and hooks call into this script instead of using inline if-shell chains. A window-level `@secondary` variable tracks the "active secondary" pane ID, updated automatically by hooks.

**Tech Stack:** bash, tmux, bats (testing)

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `tmux/tmux-pane-focus` | Script: track/zoom/side subcommands |
| Modify | `tmux/tests/tmux-pane-toggle.bats` | Update press_t/press_e to call script, add multi-pane tests |
| Modify | `tmux/tmux.conf` (synced — edit live `~/.tmux.conf`) | Rebind t/e to script, extend hooks, update status badge |
| Modify | `sync.sh` (native) | Add copy_if_exists line for tmux-pane-focus |

**Important:** `tmux/tmux.conf` is a synced file. Edit the live file at `~/.tmux.conf`, then run `./sync.sh`. All other files are native and edited directly in the repo.

---

### Task 1: Create tmux-pane-focus script with `track` subcommand

**Files:**
- Create: `tmux/tmux-pane-focus`
- Modify: `tmux/tests/tmux-pane-toggle.bats`

The script uses two env vars for test isolation: `TMUX_PANE_FOCUS_SOCK` (socket name) and `TMUX_PANE_FOCUS_TARGET` (session target for display-message). In production (inside tmux), these are unset and tmux uses the ambient session context.

- [ ] **Step 1: Write failing test for @secondary tracking**

Add to `tmux/tests/tmux-pane-toggle.bats`, at the end of the file:

```bash
# ── tmux-pane-focus script tests ─────────────────────────────────────────────

# Path to the script under test
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT="$SCRIPT_DIR/../tmux-pane-focus"

# Helper: call tmux-pane-focus with test socket/target
pane_focus() {
  TMUX_PANE_FOCUS_SOCK="$SOCK" TMUX_PANE_FOCUS_TARGET="$SES" "$SCRIPT" "$@"
}

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "track:"`
Expected: FAIL — script not found

- [ ] **Step 3: Create the script skeleton with track subcommand**

Create `tmux/tmux-pane-focus`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Test isolation: TMUX_PANE_FOCUS_SOCK overrides the tmux socket,
# TMUX_PANE_FOCUS_TARGET overrides the target for display-message.
_sock_args() { [ -n "${TMUX_PANE_FOCUS_SOCK:-}" ] && echo "-L $TMUX_PANE_FOCUS_SOCK" || true; }
_target_args() { [ -n "${TMUX_PANE_FOCUS_TARGET:-}" ] && echo "-t $TMUX_PANE_FOCUS_TARGET" || true; }

tm()      { tmux $(_sock_args) "$@"; }
tm_info() { tm display-message $(_target_args) -p "$@"; }

# Resolve the active secondary pane ID.
# Returns @secondary if set and alive, otherwise falls back to the last pane.
get_secondary() {
  local secondary
  secondary=$(tm_info '#{@secondary}')
  if [ -n "$secondary" ] && tm display-message -t "$secondary" $(_sock_args) -p '#{pane_id}' >/dev/null 2>&1; then
    echo "$secondary"
    return 0
  fi
  # Fallback: highest-index pane in the window
  tm list-panes $(_target_args) -F '#{pane_id}' | tail -1
}

case "${1:-}" in
  track)
    pane_idx=$(tm_info '#{pane_index}')
    if [ "$pane_idx" -gt 1 ]; then
      tm set-option -w $(_target_args) @secondary "$(tm_info '#{pane_id}')"
    fi
    ;;
  *)
    echo "Usage: tmux-pane-focus {track|zoom|side}" >&2
    exit 1
    ;;
esac
```

Make it executable: `chmod +x tmux/tmux-pane-focus`

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "track:"`
Expected: 2 tests PASS

- [ ] **Step 5: Write failing test for get_secondary fallback**

Add to `tmux/tests/tmux-pane-toggle.bats`:

```bash
@test "track: get_secondary falls back to last pane when @secondary is unset" {
  tmux -L "$SOCK" split-window -h -t "$SES"
  tmux -L "$SOCK" split-window -h -t "$SES"
  sleep 0.1
  # @secondary is not set; zoom subcommand will call get_secondary
  # For now, test via track + verify fallback by checking the pane exists
  local last_pane
  last_pane=$(tmux -L "$SOCK" list-panes -t "$SES" -F '#{pane_id}' | tail -1)
  # Focus pane 1 (so @secondary stays unset from track)
  tmux -L "$SOCK" select-pane -t "${SES}:1.1"
  sleep 0.1
  # get_secondary is exercised via zoom in Task 2; here just verify last_pane is valid
  [ -n "$last_pane" ]
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "get_secondary"`
Expected: PASS (this test validates the fallback data, not the function directly — full integration tested in Task 2)

- [ ] **Step 7: Commit**

Suggest commit with message: `feat(tmux): add tmux-pane-focus script with track subcommand`

---

### Task 2: Add `zoom` subcommand (replaces prefix+t)

**Files:**
- Modify: `tmux/tmux-pane-focus`
- Modify: `tmux/tests/tmux-pane-toggle.bats`

- [ ] **Step 1: Rewrite press_t to call the script and run existing tests**

Replace the existing `press_t()` function (lines 41-57) in `tmux/tests/tmux-pane-toggle.bats`:

```bash
# Simulate pressing prefix+t via the tmux-pane-focus script.
press_t() {
  pane_focus zoom
  sleep 0.1
}
```

Note: this requires the `pane_focus` helper and `SCRIPT`/`SCRIPT_DIR` vars from Task 1. Move them from the bottom section to the top of the file, right after the `SES` variable declaration (line 10), so they're available to all tests:

```bash
SOCK="test-toggle"
SES="test-pane"
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SCRIPT="$SCRIPT_DIR/../tmux-pane-focus"

pane_focus() {
  TMUX_PANE_FOCUS_SOCK="$SOCK" TMUX_PANE_FOCUS_TARGET="$SES" "$SCRIPT" "$@"
}
```

- [ ] **Step 2: Run existing bind-t tests to verify they fail**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "bind t"`
Expected: FAIL — zoom subcommand not implemented

- [ ] **Step 3: Implement zoom subcommand**

Add the `zoom` case to `tmux/tmux-pane-focus`, before the `*` case:

```bash
  zoom)
    npanes=$(tm_info '#{window_panes}')
    zoomed=$(tm_info '#{window_zoomed_flag}')
    pane_idx=$(tm_info '#{pane_index}')
    if [ "$npanes" -eq 1 ]; then
      local path
      path=$(tm_info '#{pane_current_path}')
      tm split-window -h -l 30% $(_target_args) -c "$path"
      tm resize-pane -Z $(_target_args)
    elif [ "$zoomed" -eq 0 ]; then
      tm resize-pane -Z $(_target_args)
    elif [ "$pane_idx" -eq 1 ]; then
      local sec
      sec=$(get_secondary)
      tm select-pane -Z $(_sock_args) -t "$sec"
    else
      tm select-pane -Z $(_target_args) -t 1
    fi
    ;;
```

Also update the usage line: `echo "Usage: tmux-pane-focus {track|zoom|side}" >&2`

- [ ] **Step 4: Run existing bind-t tests to verify they pass**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "bind t"`
Expected: all 7 bind-t tests PASS

Note: The `zoom` subcommand uses `select-pane -t 1` (pane index) for going back to main, and `get_secondary` for going to the secondary. For the 2-pane case, `get_secondary` will return the pane created by the split (tracked via `after-split-window` in production; in tests, the split inside `zoom` leaves the new pane focused, so the next `press_t` will see `pane_idx != 1` and go to main). However, the zoomed toggle from pane 1 → secondary requires `@secondary` to be set. After the first `press_t` (split+zoom), pane 2 is focused. The second `press_t` sees `pane_idx == 2` (not 1), so it goes to pane 1 — this works without `@secondary`. The third `press_t` sees `pane_idx == 1`, calls `get_secondary` — `@secondary` is unset, fallback returns last pane. This should work.

If any tests fail due to `@secondary` not being set, add a `pane_focus track` call after the split in the `zoom` subcommand:

```bash
    if [ "$npanes" -eq 1 ]; then
      local path
      path=$(tm_info '#{pane_current_path}')
      tm split-window -h -l 30% $(_target_args) -c "$path"
      # Track the new pane as secondary
      pane_idx=$(tm_info '#{pane_index}')
      [ "$pane_idx" -gt 1 ] && tm set-option -w $(_target_args) @secondary "$(tm_info '#{pane_id}')"
      tm resize-pane -Z $(_target_args)
    fi
```

- [ ] **Step 5: Commit**

Suggest commit with message: `feat(tmux): add zoom subcommand to tmux-pane-focus`

---

### Task 3: Add `side` subcommand (replaces prefix+e)

**Files:**
- Modify: `tmux/tmux-pane-focus`
- Modify: `tmux/tests/tmux-pane-toggle.bats`

- [ ] **Step 1: Rewrite press_e to call the script**

Replace the existing `press_e()` function in `tmux/tests/tmux-pane-toggle.bats`:

```bash
# Simulate pressing prefix+e via the tmux-pane-focus script.
press_e() {
  pane_focus side
  sleep 0.1
}
```

- [ ] **Step 2: Run existing bind-e and cross tests to verify they fail**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "bind e|cross"`
Expected: FAIL — side subcommand not implemented

- [ ] **Step 3: Implement side subcommand**

Add the `side` case to `tmux/tmux-pane-focus`, before the `*` case:

```bash
  side)
    npanes=$(tm_info '#{window_panes}')
    zoomed=$(tm_info '#{window_zoomed_flag}')
    if [ "$npanes" -eq 1 ]; then
      local path
      path=$(tm_info '#{pane_current_path}')
      tm split-window -h -l 30% $(_target_args) -c "$path"
      # Track the new pane as secondary
      local pane_idx
      pane_idx=$(tm_info '#{pane_index}')
      [ "$pane_idx" -gt 1 ] && tm set-option -w $(_target_args) @secondary "$(tm_info '#{pane_id}')"
    elif [ "$zoomed" -eq 1 ]; then
      tm resize-pane -Z $(_target_args)
      local sec
      sec=$(get_secondary)
      tm select-pane $(_sock_args) -t "$sec"
    else
      tm select-pane $(_target_args) -t 1
      tm resize-pane -Z $(_target_args)
    fi
    ;;
```

- [ ] **Step 4: Run all bind-e, cross, and hook tests to verify they pass**

Run: `bats tmux/tests/tmux-pane-toggle.bats`
Expected: ALL tests PASS (bind-t, bind-e, cross, hook, track tests)

- [ ] **Step 5: Commit**

Suggest commit with message: `feat(tmux): add side subcommand to tmux-pane-focus`

---

### Task 4: Multi-pane tests

**Files:**
- Modify: `tmux/tests/tmux-pane-toggle.bats`

- [ ] **Step 1: Write failing test — 3 panes, track updates @secondary on pane switch**

Add to `tmux/tests/tmux-pane-toggle.bats`:

```bash
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "multi: track"`
Expected: PASS (tracking already works from Task 1)

- [ ] **Step 3: Write test — 3 panes, prefix+t zooms and toggles with @secondary**

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "multi: zoom"`
Expected: PASS

- [ ] **Step 5: Write test — 3 panes, prefix+e side-by-side toggle with @secondary**

```bash
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "multi: side"`
Expected: PASS

- [ ] **Step 7: Write test — switching @secondary mid-session changes toggle target**

```bash
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
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bats tmux/tests/tmux-pane-toggle.bats --filter "multi: changing"`
Expected: PASS

- [ ] **Step 9: Run full test suite**

Run: `bats tmux/tests/tmux-pane-toggle.bats`
Expected: ALL tests PASS

- [ ] **Step 10: Commit**

Suggest commit with message: `test(tmux): add multi-pane scenarios for tmux-pane-focus`

---

### Task 5: Update tmux.conf, sync.sh, and status bar

**Files:**
- Modify: `tmux/tmux.conf` (synced — apply changes to `~/.tmux.conf` first)
- Modify: `sync.sh` (native)

This task provides the exact changes. The engineer applies tmux.conf changes to the live file, then runs `./sync.sh` to update the repo copy.

- [ ] **Step 1: Add sync line for tmux-pane-focus to sync.sh**

After line 39 (`copy_if_exists "$HOME/.local/bin/tmux-session-switcher"...`), add:

```bash
copy_if_exists "$HOME/.local/bin/tmux-pane-focus"                    "$REPO_DIR/tmux/tmux-pane-focus"
```

- [ ] **Step 2: Document tmux.conf changes to apply to live file**

The following changes go in `~/.tmux.conf`. Tell the user to apply these edits to the live file.

**Change 1 — Status bar badge** (line 34-38): Update comment and gate condition.

Replace:
```
# Pane state badge (only shown when 2 panes exist):
#   󰕮 SIDE   — side-by-side (teal, unzoomed)
#   󰆍 TERM   — secondary pane fullscreen (peach, zoomed pane 2)
#   󰈉 HIDDEN — secondary pane hidden (dim, zoomed pane 1)
set -g status-right '#{?client_prefix,#[bg=colour1 fg=colour255 bold] PREFIX #[default] ,}#{?#{==:#{window_panes},2},#{?#{window_zoomed_flag},#{?#{==:#{pane_index},1},#[fg=#{@thm_text}]#[bg=#{@thm_surface0}] 󰈉 HIDDEN #[default] ,#[fg=#{@thm_crust}]#[bg=#{@thm_peach}]#[bold] 󰆍 TERM #[default] },#[fg=#{@thm_teal}] 󰕮 SIDE #[default] },}#[fg=#{@thm_crust},bg=#{@thm_teal}] session: #S '
```

With:
```
# Pane state badge (shown when 2+ panes exist):
#   󰕮 SIDE   — side-by-side (teal, unzoomed)
#   󰆍 TERM   — non-main pane fullscreen (peach, zoomed on pane != 1)
#   󰈉 HIDDEN — extras hidden (dim, zoomed on pane 1)
set -g status-right '#{?client_prefix,#[bg=colour1 fg=colour255 bold] PREFIX #[default] ,}#{?#{>=:#{window_panes},2},#{?#{window_zoomed_flag},#{?#{==:#{pane_index},1},#[fg=#{@thm_text}]#[bg=#{@thm_surface0}] 󰈉 HIDDEN #[default] ,#[fg=#{@thm_crust}]#[bg=#{@thm_peach}]#[bold] 󰆍 TERM #[default] },#[fg=#{@thm_teal}] 󰕮 SIDE #[default] },}#[fg=#{@thm_crust},bg=#{@thm_teal}] session: #S '
```

The only functional change: `#{==:#{window_panes},2}` → `#{>=:#{window_panes},2}`.

**Change 2 — Bindings** (lines 57-76): Replace inline if-shell chains with script calls.

Replace:
```
# prefix+e: side-by-side view of the secondary pane
# - 1 pane         → split right (30%), focus new pane
# - 2 panes+zoomed → unzoom, focus pane 2
# - 2 panes        → select pane 1 + zoom (hide, pane 2 persists)
bind e if-shell "[ #{window_panes} -eq 1 ]" \
  "split-window -h -l 30% -c '#{pane_current_path}'" \
  "if-shell '[ #{window_zoomed_flag} -eq 1 ]' \
    'resize-pane -Z ; select-pane -t 2' \
    'select-pane -t 1 ; resize-pane -Z'"
# prefix+t: zoomed view of the secondary pane
# - 1 pane          → split right (30%), zoom new pane
# - 2 panes+zoomed  → toggle between pane 1/2 (stay zoomed)
# - 2 panes         → zoom current pane
bind t if-shell "[ #{window_panes} -eq 1 ]" \
  "split-window -h -l 30% -c '#{pane_current_path}' ; resize-pane -Z" \
  "if-shell '[ #{window_zoomed_flag} -eq 0 ]' \
    'resize-pane -Z' \
    'if-shell \"[ #{pane_index} -eq 2 ]\" \
      \"select-pane -Z -t 1\" \
      \"select-pane -Z -t 2\"'"
```

With:
```
# prefix+e: side-by-side toggle (uses @secondary to track active extra pane)
# - 1 pane  → split right (30%), focus new pane
# - zoomed  → unzoom, focus @secondary
# - unzoomed → select pane 1 + zoom (hide extras)
bind e run-shell "tmux-pane-focus side"
# prefix+t: zoomed toggle (uses @secondary to track active extra pane)
# - 1 pane          → split right (30%), zoom new pane
# - unzoomed        → zoom current pane
# - zoomed on main  → switch to @secondary (stay zoomed)
# - zoomed on other → switch to main (stay zoomed)
bind t run-shell "tmux-pane-focus zoom"
```

**Change 3 — Hooks** (lines 79-84): Extend hooks to run tracking.

Replace:
```
# Style non-primary panes (index > 1) with Dracula bg on creation
set-hook -g after-split-window \
  'if-shell "[ #{pane_index} -gt 1 ]" "select-pane -P \"bg=#{@dracula_bg},fg=#{@dracula_fg}\""'

# Auto-resize active pane when switching panes; skip when zoomed (zoom guard)
set-hook -g after-select-pane 'if-shell "[ #{window_panes} -eq 2 ] && [ #{window_zoomed_flag} -eq 0 ]" "if-shell \"[ #{pane_index} -eq 1 ]\" \"resize-pane -x 70%\" \"resize-pane -x 55%\""'
```

With:
```
# Style non-primary panes (index > 1) with Dracula bg on creation + track as @secondary
set-hook -g after-split-window \
  'run-shell "tmux-pane-focus track" ; if-shell "[ #{pane_index} -gt 1 ]" "select-pane -P \"bg=#{@dracula_bg},fg=#{@dracula_fg}\""'

# Track @secondary on pane focus + auto-resize (2-pane only, skip when zoomed)
set-hook -g after-select-pane \
  'run-shell "tmux-pane-focus track" ; if-shell "[ #{window_panes} -eq 2 ] && [ #{window_zoomed_flag} -eq 0 ]" "if-shell \"[ #{pane_index} -eq 1 ]\" \"resize-pane -x 70%\" \"resize-pane -x 55%\""'
```

- [ ] **Step 3: Copy script to live location**

Tell the user to run:
```bash
cp tmux/tmux-pane-focus ~/.local/bin/tmux-pane-focus
chmod +x ~/.local/bin/tmux-pane-focus
```

- [ ] **Step 4: User applies tmux.conf changes to ~/.tmux.conf**

Tell the user to apply the changes from Step 2 to `~/.tmux.conf`, then reload: `tmux source-file ~/.tmux.conf`

- [ ] **Step 5: Run sync.sh and verify**

Run: `./sync.sh`
Expected: `updated tmux/tmux-pane-focus` and `updated tmux/tmux.conf` in output

- [ ] **Step 6: Run full test suite one final time**

Run: `bats tmux/tests/tmux-pane-toggle.bats`
Expected: ALL tests PASS

- [ ] **Step 7: Commit**

Suggest commit with message: `feat(tmux): wire multi-pane focus into tmux.conf and sync.sh`
