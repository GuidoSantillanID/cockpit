#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../tmux-session-switcher"

setup() {
  # Source the script's functions without executing the main block
  # shellcheck disable=SC1090
  source "$SCRIPT"
}

# ── relative_time ────────────────────────────────────────────────────────────

@test "relative_time: seconds" {
  run relative_time 30
  [ "$output" = "30s" ]
}

@test "relative_time: minutes" {
  run relative_time 120
  [ "$output" = "2m" ]
}

@test "relative_time: hours" {
  run relative_time 7200
  [ "$output" = "2h" ]
}

@test "relative_time: days" {
  run relative_time 172800
  [ "$output" = "2d" ]
}

# ── window_claude_status ──────────────────────────────────────────────────────

@test "window_claude_status: running when running flag is 1" {
  run window_claude_status "1" ""
  [ "$output" = "running" ]
}

@test "window_claude_status: done when done flag set" {
  run window_claude_status "" "done"
  [ "$output" = "done" ]
}

@test "window_claude_status: none when both empty" {
  run window_claude_status "" ""
  [ "$output" = "none" ]
}

# ── category_for_age ──────────────────────────────────────────────────────────
# Signature: category_for_age <age_seconds> → "active" or "inactive"
# Active: accessed within 2 days (172800 seconds); inactive: older

@test "category_for_age: active when within 2 days" {
  run category_for_age 3600      # 1h ago
  [ "$output" = "active" ]
}

@test "category_for_age: active at exactly 2 days boundary" {
  run category_for_age 172800    # exactly 2 days
  [ "$output" = "active" ]
}

@test "category_for_age: inactive when older than 2 days" {
  run category_for_age 172801    # 2 days + 1 second
  [ "$output" = "inactive" ]
}

@test "category_for_age: inactive when 4 days old" {
  run category_for_age 345600    # 4 days
  [ "$output" = "inactive" ]
}

# ── emit_header ───────────────────────────────────────────────────────────────

@test "emit_header: has 3 US-delimited fields" {
  local US=$'\x1f'
  run emit_header "Yesterday"
  local field3
  field3=$(printf '%s' "$output" | cut -d"$US" -f3)
  [ "$field3" = "" ]
}

@test "emit_header: field 1 contains the label" {
  local US=$'\x1f'
  run emit_header "Yesterday"
  local field1
  field1=$(printf '%s' "$output" | cut -d"$US" -f1)
  [[ "$field1" == *"Yesterday"* ]]
}

# ── emit_spacer ───────────────────────────────────────────────────────────────

@test "emit_spacer: has 3 US-delimited fields with empty field 3" {
  local US=$'\x1f'
  run emit_spacer
  local field3
  field3=$(printf '%s' "$output" | cut -d"$US" -f3)
  [ "$field3" = "" ]
}

# ── trunc ────────────────────────────────────────────────────────────────────

@test "trunc: short string returned unchanged" {
  run trunc "short"
  [ "$output" = "short" ]
}

@test "trunc: string at exact max (20) returned unchanged" {
  run trunc "12345678901234567890"
  [ "$output" = "12345678901234567890" ]
}

@test "trunc: string one over max truncated with ellipsis" {
  run trunc "123456789012345678901"
  [ "$output" = "1234567890123456789…" ]
}

@test "trunc: long branch name truncated to 19 chars plus ellipsis" {
  run trunc "GP-1167-Clean-Up-the-Dotnet-Controllers-and-APIs"
  [ "$output" = "GP-1167-Clean-Up-th…" ]
}

# ── build_list ────────────────────────────────────────────────────────────────

# Mock tmux to return canned data:
#   _default: last_attached = 4 days ago (inactive timestamp, but always pinned first)
#   sessionA: last_attached = 1h ago (active)
#   sessionB: last_attached = 4 days ago (inactive)
#   zebra:    last_attached = 2h ago (active, sorts after sessionA alphabetically)
# All sessions have one window each.
setup_tmux_mock() {
  local now
  now=$(date +%s)
  MOCK_TS_ACTIVE_1=$(( now - 3600 ))        # 1h ago — active
  MOCK_TS_ACTIVE_2=$(( now - 7200 ))        # 2h ago — active
  MOCK_TS_INACTIVE=$(( now - 86400 * 4 ))   # 4 days ago — inactive
  export MOCK_TS_ACTIVE_1 MOCK_TS_ACTIVE_2 MOCK_TS_INACTIVE

  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA\n%s|sessionB\n%s|zebra\n%s|_default\n' \
          "$MOCK_TS_ACTIVE_1" "$MOCK_TS_INACTIVE" "$MOCK_TS_ACTIVE_2" "$MOCK_TS_INACTIVE"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/home/user/projectA|1||\n'
        printf 'sessionB|0|dev|zsh|/home/user/projectB|1||\n'
        printf 'zebra|0|dev|zsh|/home/user/projectZ|1||\n'
        printf '_default|0|dev|zsh|/home/user/default|1||\n'
        ;;
      "list-panes -a")
        # sessionA has 2 panes (claude + zsh) to exercise multi-pane combined label
        printf 'sessionA|0|0|claude|/home/user/projectA|1||\n'
        printf 'sessionA|0|1|zsh|/home/user/projectA|0||\n'
        printf 'sessionB|0|0|zsh|/home/user/projectB|1||\n'
        printf 'zebra|0|0|zsh|/home/user/projectZ|1||\n'
        printf '_default|0|0|zsh|/home/user/default|1||\n'
        ;;
    esac
  }
  export -f tmux
}

@test "build_list: data lines use US delimiter with 3 fields" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  local data_lines
  data_lines=$(printf '%s\n' "${lines[@]}" | grep -v '^POS:' | grep "$US")
  [ -n "$data_lines" ]
  # Every non-empty line must have exactly 2 US chars (3 fields)
  while IFS= read -r line; do
    local count
    count=$(printf '%s' "$line" | tr -cd "$US" | wc -c | tr -d ' ')
    [ "$count" -eq 2 ]
  done <<< "$data_lines"
}

@test "build_list: _default session always appears first" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # _default must be the very first session row (field 3 = s:_default)
  local first_session_key=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == s:* ]] && { first_session_key="$key"; break; }
  done
  [ "$first_session_key" = "s:_default" ]
}

@test "build_list: active sessions sorted alphabetically after _default" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # sessionA and zebra are both active; sessionA should come before zebra
  local pos_a pos_z i=0
  for line in "${lines[@]}"; do
    i=$(( i + 1 ))
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:sessionA" ]] && pos_a=$i
    [[ "$key" == "s:zebra" ]]    && pos_z=$i
  done
  [ -n "$pos_a" ]
  [ -n "$pos_z" ]
  [ "$pos_a" -lt "$pos_z" ]
}

@test "build_list: inactive sessions appear after all active sessions" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # sessionB is inactive; zebra is active — zebra must come before sessionB
  local pos_b pos_z i=0
  for line in "${lines[@]}"; do
    i=$(( i + 1 ))
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:sessionB" ]] && pos_b=$i
    [[ "$key" == "s:zebra" ]]    && pos_z=$i
  done
  [ -n "$pos_b" ]
  [ -n "$pos_z" ]
  [ "$pos_z" -lt "$pos_b" ]
}

@test "build_list: Inactive header appears before inactive sessions" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # Find the line immediately before sessionB — its field 3 must be empty (header)
  local found_header=0
  local prev_key=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:sessionB" ]]; then
      [[ "$prev_key" == "" ]] && found_header=1
    fi
    prev_key="$key"
  done
  [ "$found_header" -eq 1 ]
}

@test "build_list: no header before active sessions" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # _default is first; the first key in the output must be a session/window key, not empty
  local first_key=""
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    first_key=$(printf '%s' "$line" | cut -d"$US" -f3)
    break
  done
  [[ "$first_key" == s:* || "$first_key" == w:* ]]
}

@test "build_list: header/spacer lines have empty field 3" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == s:* || "$key" == w:* || "$key" == "" ]] || {
      echo "unexpected field 3: '$key'"
      return 1
    }
  done
}

@test "build_list: POS line emitted when session arg provided" {
  setup_tmux_mock
  run build_list "sessionA"
  [[ "${lines[0]}" == POS:* ]]
}

@test "fzf invocation: pos() fires in load binding after reload-sync, not in start binding" {
  # pos() in start: fires before reload-sync resets the list, so cursor reverts to 1.
  # It must be chained after reload-sync in the load: binding instead.
  ! grep -q 'start:pos(' "$SCRIPT"
  grep -qE 'load:reload-sync[^"]*\+pos\(' "$SCRIPT"
}

@test "fzf invocation: load binding contains unbind(load) to prevent infinite reload" {
  # Without unbind(load), every reload (e.g. ctrl-d) would re-trigger the load binding.
  grep -qE 'load:reload-sync[^"]*\+unbind\(load\)' "$SCRIPT"
}

@test "build_list: no POS line emitted when called without session arg (--list reload path)" {
  setup_tmux_mock
  run build_list ""
  [[ "${lines[0]}" != POS:* ]]
}

@test "build_list: fast (skip_git) and full load produce same line count" {
  # start_pos is computed from the fast list; it must index correctly into the full list.
  setup_tmux_mock
  local fast_count full_count
  fast_count=$(build_list "sessionA" "1" | tail -n +2 | wc -l | tr -d ' ')
  full_count=$(build_list "sessionA" | tail -n +2 | wc -l | tr -d ' ')
  [ "$fast_count" -eq "$full_count" ]
}

@test "build_list: POS points to sessionA line" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list "sessionA"
  local pos
  pos=$(printf '%s' "${lines[0]}" | sed 's/^POS://')
  local actual_line
  actual_line=$(printf '%s\n' "${lines[@]}" | tail -n +2 | sed -n "${pos}p")
  local key
  key=$(printf '%s' "$actual_line" | cut -d"$US" -f3)
  [ "$key" = "s:sessionA" ]
}

@test "build_list: empty session list produces no output" {
  tmux() {
    case "$1 $2" in
      "list-sessions -F") : ;;
      "list-windows -a")  : ;;
      *) command tmux "$@" ;;
    esac
  }
  export -f tmux
  run build_list ""
  # No data lines (only possibly a POS line if arg given, but arg is "")
  local data_lines
  data_lines=$(printf '%s\n' "${lines[@]}" | grep -v '^POS:' | grep -v '^$' || true)
  [ -z "$data_lines" ]
}

# ── padding before Inactive header (#1) ──────────────────────────────────────

@test "build_list: spacer line emitted before Inactive header" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # The line immediately before the Inactive header (empty field 3 with "Inactive" in field 1)
  # must itself be an empty-field-3 line (spacer), not a session row
  local prev_key="" found=0
  for line in "${lines[@]}"; do
    local key f1
    f1=$(printf '%s' "$line" | cut -d"$US" -f1)
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$f1" == *"Inactive"* ]]; then
      [[ "$prev_key" == "" ]] && found=1
      break
    fi
    prev_key="$key"
  done
  [ "$found" -eq 1 ]
}

# ── column order: repo first, status last (#5) ───────────────────────────────

@test "build_list: running window shows dirname in detail (no 'running' label)" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|dev|zsh|/home/user/myproject|1|1|\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # icon already signals running — no need for the text label
  [[ "$detail" == *"myproject"* ]]
  [[ "$detail" != *"running"* ]]
}

# ── window name dedup (#7) ───────────────────────────────────────────────────

@test "build_list: window named same as session shown as 'shell' when idle" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|wt\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        # window_name=wt (same as session), cmd=zsh (idle shell), no claude running
        printf 'wt|0|wt|zsh|/home/user/wt|1||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  # Find the window row and check field 1 contains "shell", not "wt"
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:wt:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"shell"* ]]
}

@test "build_list: window named differently from session keeps its name" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myapp\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myapp|0|terminal|zsh|/home/user/other-dir|1||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"terminal"* ]]
  [[ "$field1" != *"shell"* ]]
}

# ── git_branch_for_path (#6) ─────────────────────────────────────────────────

@test "git_branch_for_path: returns branch name for git repo" {
  # Use the current repo (cockpit) which is on a known branch
  local branch
  branch=$(git_branch_for_path "$BATS_TEST_DIRNAME/../..")
  [ -n "$branch" ]
}

@test "git_branch_for_path: returns empty for non-git directory" {
  local branch
  branch=$(git_branch_for_path "/tmp")
  [ -z "$branch" ]
}

@test "build_list: non-main branch shown in window detail" {
  local now
  now=$(date +%s)
  # Create a temp dir and fake git repo on a feature branch
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/my-feature 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/my-feature
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|terminal|zsh|%s|1||\n' "$tmpdir"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  # Window detail should contain "feat/my-feature"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"feat/my-feature"* ]]
}

@test "build_list: main branch not shown in window detail" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b main 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/main
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|terminal|zsh|%s|1||\n' "$tmpdir"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *" main"* ]]
}

@test "build_list: branch color uses actual ESC bytes, not literal backslash-033" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/color-test 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/color-test
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|terminal|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Must NOT contain literal "\033" (backslash + 033) — means ANSI not pre-rendered
  [[ "$detail" != *'\033'* ]]
}

# ── multi-pane windows in main list ──────────────────────────────────────────

@test "build_list: multi-pane idle window shows window name with dot-count" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        # No @is_claude_running — idle multi-pane window
        printf 'myproject|0|dev|node|/home/user/myproject|1||\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|node|/home/user/myproject|1||\n'
        printf 'myproject|0|1|zsh|/home/user/myproject|0||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1="" field2=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      field2=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$field2" == *"󰿦 2"* ]]
  [[ "$field1" != *" / "* ]]
}

@test "build_list: multi-pane window with Claude running uses window name not pane commands" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        # Window renamed to "󰚩 main" by claude() wrapper, @is_claude_running=1
        printf 'myproject|0|󰚩 main|2.1.83|/home/user/myproject|1|1|\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|2.1.83|/home/user/myproject|1|1|\n'
        printf 'myproject|0|1|zsh|/home/user/myproject|0||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1="" field2=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      field2=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Name column clean; pane indicator in detail column (field 2)
  [[ "$field1" == *"main"* ]]
  [[ "$field2" == *"󰿦 2"* ]]
  [[ "$field1" != *"2.1.83"* ]]
  [[ "$field1" != *" / "* ]]
}

@test "build_list: multi-pane idle window shows dot-count suffix" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        # window name same as session → dedup to "shell"
        printf 'myproject|0|myproject|zsh|/home/user/myproject|1||\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|zsh|/home/user/myproject|1||\n'
        printf 'myproject|0|1|zsh|/home/user/myproject|0||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1="" field2=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      field2=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Name column clean; pane indicator in detail column (field 2)
  [[ "$field1" == *"shell"* ]]
  [[ "$field2" == *"󰿦 2"* ]]
  [[ "$field1" != *"shell 󰿦"* ]]
  [[ "$field1" != *" / "* ]]
}

@test "build_list: pane indicator is separate from window name" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|󰚩 main|2.1.83|/home/user/myproject|1|1|\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|2.1.83|/home/user/myproject|1|1|\n'
        printf 'myproject|0|1|zsh|/home/user/myproject|0||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1="" field2=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      field2=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Name column (field 1) stays clean; pane indicator in detail column (field 2)
  [[ "$field1" == *"main"* ]]
  [[ "$field2" == *"󰿦 2"* ]]
  [[ "$field1" != *"󰿦"* ]]
}

@test "build_list: single-pane window does not show slash separator" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|dev|zsh|/home/user/myproject|1||\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|zsh|/home/user/myproject|1||\n'
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" != *" / "* ]]
}

# ── preview_session: GIT section restructure ─────────────────────────────────

@test "preview_session: GIT header line includes branch name" {
  local tmpdir
  tmpdir=$(mktemp -d)
  git -C "$tmpdir" init -q
  git -C "$tmpdir" checkout -q -b feat/preview-branch 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/preview-branch
  local now_ts
  now_ts=$(date +%s)
  tmux() {
    case "$*" in
      *"#{session_path}"*)     echo "$tmpdir" ;;
      "list-panes -t"*)        printf '0|0|shell|zsh|%s|1||\n' "$tmpdir" ;;
      "list-windows -t"*)      printf 'dummy\n' ;;
      *"#{session_attached}"*) echo "0" ;;
      *"#{session_created}"*)  echo "$(( now_ts - 3600 ))" ;;
    esac
  }
  export -f tmux
  run preview_session "mysession"
  rm -rf "$tmpdir"
  local git_line=""
  for line in "${lines[@]}"; do
    if [[ "$line" == *"GIT"* ]]; then
      git_line="$line"
      break
    fi
  done
  [[ "$git_line" == *"feat/preview-branch"* ]]
}

# ── preview_session: multi-pane window sub-rows ───────────────────────────────

@test "preview_session: multi-pane window shows sub-rows for each pane" {
  local tmpdir
  tmpdir=$(mktemp -d)
  local now_ts
  now_ts=$(date +%s)
  tmux() {
    case "$*" in
      *"#{session_path}"*)     echo "$tmpdir" ;;
      "list-panes -s -t"*)
        printf '0|0|dev|claude|%s|1|1|\n' "$tmpdir"
        printf '0|1|dev|zsh|%s|0||\n' "$tmpdir"
        ;;
      "list-windows -t"*)      printf 'dummy\n' ;;
      *"#{session_attached}"*) echo "0" ;;
      *"#{session_created}"*)  echo "$(( now_ts - 3600 ))" ;;
    esac
  }
  export -f tmux
  run preview_session "mysession"
  rm -rf "$tmpdir"
  local in_windows=0 window_section_lines=0
  for line in "${lines[@]}"; do
    if [[ "$line" == *"WINDOWS"* ]]; then
      in_windows=1
      continue
    fi
    if [[ "$in_windows" -eq 1 ]]; then
      [[ "$line" == *"INFO"* ]] && break
      [[ -n "$line" ]] && window_section_lines=$(( window_section_lines + 1 ))
    fi
  done
  # 2 panes in 1 window: header (active/claude) + 1 sub-row (zsh differs) = 2 lines
  # identical-to-header panes are suppressed
  [ "$window_section_lines" -ge 2 ]
}

# ── preview_session: git icon glyph (#2 bug) ─────────────────────────────────

@test "preview_session: git section uses nerd font branch glyph, not Unicode ⎇" {
  # preview_session calls tmux live; test only the static printf format
  # We check that the script file itself uses  not ⎇ in the preview printf
  local branch_glyph
  branch_glyph=$(grep -o '. %s · %s' "$BATS_TEST_DIRNAME/../tmux-session-switcher" | head -1 | cut -c1)
  # ⎇ is multi-byte U+2387; Nerd Font  is U+E0A0 — verify it's not the ⎇ char
  local expected_bad=$'\xe2\x8e\x87'  # UTF-8 encoding of ⎇ U+2387
  local actual_char
  actual_char=$(grep -o '. %s · %s' "$BATS_TEST_DIRNAME/../tmux-session-switcher" | head -1 | cut -c1-1)
  [ "$actual_char" != "$(printf '%b' '\xe2\x8e\x87')" ]
}

# ── pane_label_for_cmd ────────────────────────────────────────────────────────

@test "pane_label_for_cmd: zsh returns 'shell'" {
  run pane_label_for_cmd "zsh"
  [ "$output" = "shell" ]
}

@test "pane_label_for_cmd: bash returns 'shell'" {
  run pane_label_for_cmd "bash"
  [ "$output" = "shell" ]
}

@test "pane_label_for_cmd: fish returns 'shell'" {
  run pane_label_for_cmd "fish"
  [ "$output" = "shell" ]
}

@test "pane_label_for_cmd: node passes through unchanged" {
  run pane_label_for_cmd "node"
  [ "$output" = "node" ]
}

# ── window_icon ───────────────────────────────────────────────────────────────

@test "window_icon: running status returns non-empty string" {
  run window_icon "running" "zsh"
  [ -n "$output" ]
}

@test "window_icon: done status returns different output from running" {
  local running_out done_out
  running_out=$(window_icon "running" "zsh")
  done_out=$(window_icon "done" "zsh")
  [ "$running_out" != "$done_out" ]
}

@test "window_icon: none+zsh returns different output from none+node" {
  local shell_out other_out
  shell_out=$(window_icon "none" "zsh")
  other_out=$(window_icon "none" "node")
  [ "$shell_out" != "$other_out" ]
}

# ── parse_session ─────────────────────────────────────────────────────────────

@test "parse_session: s:myapp extracts myapp" {
  run parse_session "s:myapp"
  [ "$output" = "myapp" ]
}

@test "parse_session: w:myapp:0 extracts myapp" {
  run parse_session "w:myapp:0"
  [ "$output" = "myapp" ]
}

# ── panes_raw variable scope ──────────────────────────────────────────────────

@test "build_list: panes_raw does not leak to outer scope" {
  setup_tmux_mock
  panes_raw="sentinel"
  build_list "" > /dev/null
  [ "$panes_raw" = "sentinel" ]
}

# ── build_list: setup_tmux_mock multi-pane data ───────────────────────────────

@test "build_list: multi-pane data in mock produces pane-count indicator in detail for sessionA window" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  local field1="" field2=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:sessionA:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      field2=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # sessionA has 2 panes — indicator in detail column, name column clean
  [[ "$field2" == *"󰿦 2"* ]]
  [[ "$field1" != *" / "* ]]
  [[ "$field1" != *"󰿦"* ]]
}

# ── preview_session: error handling ──────────────────────────────────────────

@test "preview_session: non-existent session exits cleanly" {
  tmux() {
    case "$*" in
      *"#{session_path}"*)     echo "/tmp/cockpit-test-no-such-path-$$" ;;
      "list-panes -s -t"*)     : ;;
      *"#{session_attached}"*) echo "0" ;;
      *"#{session_created}"*)  echo "$(( $(date +%s) - 3600 ))" ;;
      *) return 1 ;;
    esac
  }
  export -f tmux
  run preview_session "nonexistent-session-xyz"
  [ "$status" -eq 0 ]
}

# ── handle_selection: robustness ─────────────────────────────────────────────

@test "handle_selection: does not call select-window when switch-client fails" {
  local tmpdir
  tmpdir=$(mktemp -d)
  export tmpdir
  tmux() {
    echo "tmux $*" >> "$tmpdir/tmux-calls.log"
    case "$1" in
      switch-client) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f tmux
  run handle_selection "w:dead-session:1"
  ! grep -q "select-window" "$tmpdir/tmux-calls.log" 2>/dev/null
  rm -rf "$tmpdir"
}

@test "handle_selection: exits cleanly when select-window fails" {
  tmux() {
    case "$1" in
      switch-client) return 0 ;;
      select-window) return 1 ;;
      *) return 0 ;;
    esac
  }
  export -f tmux
  run handle_selection "w:mysession:1"
  [ "$status" -eq 0 ]
}

# ── is_worktree_session ───────────────────────────────────────────────────────

@test "is_worktree_session: returns true for name with slash" {
  run is_worktree_session "myapp/feat"
  [ "$status" -eq 0 ]
}

@test "is_worktree_session: returns false for name without slash" {
  run is_worktree_session "myapp"
  [ "$status" -eq 1 ]
}

# ── git_is_dirty ──────────────────────────────────────────────────────────────

@test "git_is_dirty: clean repo returns false" {
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  run git_is_dirty "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 1 ]
}

@test "git_is_dirty: repo with staged changes returns true" {
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  echo "content" > "$tmpdir/file.txt"
  git -C "$tmpdir" add .
  run git_is_dirty "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
}

# ── git_is_merged ─────────────────────────────────────────────────────────────

@test "git_is_merged: HEAD on main branch returns true" {
  local tmpdir origin_dir
  tmpdir=$(mktemp -d)
  origin_dir=$(mktemp -d)
  git init -q --bare "$origin_dir"
  git clone -q "$origin_dir" "$tmpdir" 2>/dev/null
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com \
    git -C "$tmpdir" commit --allow-empty -m "init" 2>/dev/null || true
  git -C "$tmpdir" push -q origin main 2>/dev/null
  run git_is_merged "$tmpdir"
  rm -rf "$tmpdir" "$origin_dir"
  [ "$status" -eq 0 ]
}

@test "git_is_merged: unmerged feature branch returns false" {
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com \
    git -C "$tmpdir" commit --allow-empty -m "init" 2>/dev/null || true
  git -C "$tmpdir" checkout -q -b feat/unmerged 2>/dev/null
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com \
    git -C "$tmpdir" commit --allow-empty -m "feature" 2>/dev/null || true
  run git_is_merged "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -ne 0 ]
}

# ── attention badges in build_list ───────────────────────────────────────────

@test "build_list: claude done window shows green dot badge" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|/tmp|1||done\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"●"* ]]
}

@test "build_list: attention badge colors use actual ESC bytes, not literal backslash-033" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|/tmp|1||done\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Must NOT contain literal "\033" — means ANSI escape not expanded
  [[ "$detail" != *'\033'* ]]
}

@test "build_list: dirty tree shows peach diamond badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/dirty 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/dirty
  echo "content" > "$tmpdir/file.txt"
  git -C "$tmpdir" add .
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myapp:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"✦ dirty"* ]]
}

@test "build_list: worktree session with done+clean window shows stale badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/stale 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/stale
  tmux() {
    case "$1 $2" in
      # Session name "myapp/feat" has slash → is_worktree_session = true
      "list-sessions -F") printf '%s|myapp/feat\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp/feat|0|dev|zsh|%s|1||done\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp/feat:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"󰇝 stale"* ]]
}

@test "build_list: non-worktree session does not show stale badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/test 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/test
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|%s|1||done\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *"󰇝"* ]]
}

@test "build_list: inactive session shows attention count badge" {
  local now
  now=$(date +%s)
  local inactive_ts=$(( now - 86400 * 4 ))  # 4 days ago → inactive
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|oldapp\n' "$inactive_ts" ;;
      "list-windows -a")  printf 'oldapp|0|dev|zsh|/tmp|1||\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:oldapp" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"⚠"* ]]
}

@test "build_list: active session with no attention has no badge" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|/tmp|1||\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:myapp" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" != *"⚠"* ]]
}

# ── _git_lookup ───────────────────────────────────────────────────────────────

@test "_git_lookup: cache miss sets empty branch and zero flags" {
  _git_lookup "" "/some/path"
  [ "$_gl_branch" = "" ]
  [ "$_gl_dirty" = "0" ]
  [ "$_gl_merged" = "0" ]
}

@test "_git_lookup: cache hit returns correct branch name" {
  local cache
  cache=$(printf '/repo/foo\x1emain\x1e0\x1e0\n')
  _git_lookup "$cache" "/repo/foo"
  [ "$_gl_branch" = "main" ]
}

@test "_git_lookup: returns dirty=1 when path is dirty" {
  local cache
  cache=$(printf '/repo/foo\x1efeat/x\x1e1\x1e0\n')
  _git_lookup "$cache" "/repo/foo"
  [ "$_gl_dirty" = "1" ]
}

@test "_git_lookup: returns merged=1 when branch is merged" {
  local cache
  cache=$(printf '/repo/foo\x1efeat/x\x1e0\x1e1\n')
  _git_lookup "$cache" "/repo/foo"
  [ "$_gl_merged" = "1" ]
}

@test "_git_lookup: selects correct entry from multi-path cache" {
  local cache
  cache=$(printf '/repo/a\x1efeat/a\x1e0\x1e0\n/repo/b\x1efeat/b\x1e1\x1e1\n')
  _git_lookup "$cache" "/repo/b"
  [ "$_gl_branch" = "feat/b" ]
  [ "$_gl_dirty" = "1" ]
  [ "$_gl_merged" = "1" ]
}

@test "_git_lookup: unmatched path leaves globals at defaults" {
  local cache
  cache=$(printf '/repo/a\x1emain\x1e0\x1e0\n')
  _git_lookup "$cache" "/repo/other"
  [ "$_gl_branch" = "" ]
  [ "$_gl_dirty" = "0" ]
  [ "$_gl_merged" = "0" ]
}

@test "_git_lookup: returns is_wt=1 and project name from 6-field cache" {
  local cache
  cache=$(printf '/wt/branch-dir\x1efeat/x\x1e0\x1e0\x1e1\x1emyproject\n')
  _git_lookup "$cache" "/wt/branch-dir"
  [ "$_gl_branch" = "feat/x" ]
  [ "$_gl_is_wt" = "1" ]
  [ "$_gl_project" = "myproject" ]
}

@test "_git_lookup: defaults is_wt=0 and project empty for 4-field cache" {
  local cache
  cache=$(printf '/repo/foo\x1emain\x1e0\x1e0\n')
  _git_lookup "$cache" "/repo/foo"
  [ "$_gl_is_wt" = "0" ]
  [ "$_gl_project" = "" ]
}

# ── build_list: skip_git ──────────────────────────────────────────────────────

@test "build_list: skip_git omits branch from detail" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/some-branch 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/some-branch
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|terminal|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *"feat/some-branch"* ]]
}

@test "build_list: skip_git omits dirty badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/dirty 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/dirty
  echo "content" > "$tmpdir/file.txt"
  git -C "$tmpdir" add .
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myapp:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *"✦"* ]]
}

@test "build_list: skip_git omits stale badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/stale 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/stale
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp/feat\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp/feat|0|dev|zsh|%s|1||done\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp/feat:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *"󰇝"* ]]
}

@test "build_list: skip_git preserves session and window keys" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|/tmp|1||\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  local has_session_key=0 has_window_key=0
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:myapp" ]] && has_session_key=1
    [[ "$key" == "w:myapp:0" ]] && has_window_key=1
  done
  [ "$has_session_key" -eq 1 ]
  [ "$has_window_key" -eq 1 ]
}

# ── build_list: git status -b edge case ──────────────────────────────────────

@test "build_list: handles repo with no commits (shows branch name)" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/new-branch
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|terminal|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"feat/new-branch"* ]]
}

# ── build_list: parallel git cache dedup ──────────────────────────────────────

@test "build_list: dedup — same path across windows queries git once" {
  local now
  now=$(date +%s)
  local tmpdir count_file
  tmpdir=$(mktemp -d)
  count_file=$(mktemp)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/test 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/test
  export GIT_BRANCH_COUNT_FILE="$count_file"
  git() {
    case "$*" in
      *"status -b --porcelain"*)
        printf '1\n' >> "$GIT_BRANCH_COUNT_FILE"
        printf '## feat/test\n'
        ;;
      *"merge-base"*) return 1 ;;
      *) return 1 ;;
    esac
  }
  export -f git
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")
        printf 'myproject|0|win0|zsh|%s|1||\n' "$tmpdir"
        printf 'myproject|1|win1|zsh|%s|0||\n' "$tmpdir"
        ;;
    esac
  }
  export -f tmux
  build_list "" > /dev/null
  local branch_calls
  branch_calls=$(wc -l < "$count_file" | tr -d ' ')
  rm -f "$count_file"
  rm -rf "$tmpdir"
  [ "$branch_calls" -eq 1 ]
}

# ── robot-icon prefix stripping ───────────────────────────────────────────────

@test "build_list: strips robot-icon prefix from window name" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|󰚩 main|zsh|/home/user/myproject|1|1|\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  # clean_name must be "main", not "󰚩 main" (which would duplicate the wicon)
  [[ "$field1" != *"󰚩 main"* ]]
  [[ "$field1" == *"main"* ]]
}

# ── window name truncation ───────────────────────────────────────────────────

@test "build_list: truncates window name longer than 20 chars in display field" {
  local now
  now=$(date +%s)
  local long_name="GP-1167-Clean-Up-the-Dotnet-Controllers-and-APIs"
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|%s|zsh|/home/user/myproject|1||\n' "$long_name" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" != *"$long_name"* ]]
  [[ "$field1" == *"GP-1167-Clean-Up-th…"* ]]
}

# ── branch suppression when redundant with dir_name ──────────────────────────

@test "build_list: worktree window shows real project name and [wt] badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  # Create main repo with a commit so worktree add works
  git init -q "$tmpdir/myproject"
  git -C "$tmpdir/myproject" commit -q --allow-empty -m "init"
  # Create a worktree — this makes .git a file, not a directory
  git -C "$tmpdir/myproject" worktree add -q "$tmpdir/feat-branch" -b feat-branch 2>/dev/null
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|%s|1||\n' "$tmpdir/feat-branch" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myapp:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # dir_name should be the real project name, not the worktree dir
  [[ "$detail" == *"myproject"* ]]
  # branch should be shown (not suppressed — it differs from project name)
  [[ "$detail" == *"feat-branch"* ]]
  # [wt] badge must be present
  [[ "$detail" == *"[wt]"* ]]
}

@test "build_list: non-worktree window does not show [wt] badge" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  git init -q "$tmpdir"
  git -C "$tmpdir" checkout -q -b feat/x 2>/dev/null || \
    git -C "$tmpdir" symbolic-ref HEAD refs/heads/feat/x
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|%s|1||\n' "$tmpdir" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myapp:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" != *"[wt]"* ]]
}

@test "build_list: case-insensitive branch suppression" {
  local now
  now=$(date +%s)
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/MyProject"
  git init -q "$tmpdir/MyProject"
  git -C "$tmpdir/MyProject" checkout -q -b myproject 2>/dev/null || \
    git -C "$tmpdir/MyProject" symbolic-ref HEAD refs/heads/myproject
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|sess\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'sess|0|dev|zsh|%s|1||\n' "$tmpdir/MyProject" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:sess:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # Branch "myproject" should be suppressed — matches dir "MyProject" case-insensitively
  [[ "$detail" != *"myproject"* ]] || [[ "$detail" == "MyProject" ]]
}

@test "build_list: does not show branch when it ends with slash-dir_name" {
  local now
  now=$(date +%s)
  local tmpdir fake_path
  tmpdir=$(mktemp -d)
  fake_path="$tmpdir/test-test-test"
  mkdir -p "$fake_path"
  git init -q "$fake_path"
  git -C "$fake_path" checkout -q -b wt/test-test-test 2>/dev/null || \
    git -C "$fake_path" symbolic-ref HEAD refs/heads/wt/test-test-test
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myproject\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myproject|0|dev|zsh|%s|1||\n' "$fake_path" ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  rm -rf "$tmpdir"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == w:myproject:* ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # "wt/test-test-test" is redundant — dir is already "test-test-test"
  [[ "$detail" != *"wt/test-test-test"* ]]
}

@test "build_list: done window shows 'done' label in detail" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F") printf '%s|myapp\n' "$(( now - 60 ))" ;;
      "list-windows -a")  printf 'myapp|0|dev|zsh|/tmp|1||done\n' ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myapp:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  [[ "$detail" == *"● done"* ]]
}

# ── Private mode ─────────────────────────────────────────────────────────────

# Shared mock for private-mode tests.
# Arg 1: value for @switcher_show_private (empty = hidden, "1" = revealed)
setup_private_tmux_mock() {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE="${1:-}"
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV"
        printf '%s|secretSession||1\n' "$MOCK_TS_PRIV"
        printf '%s|sessionB||\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        printf 'secretSession|0|dev|zsh|/tmp|1||\n'
        printf 'sessionB|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        printf 'secretSession|0|0|zsh|/tmp|1||\n'
        printf 'sessionB|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
}

# ── Group 1: Filtering ──────────────────────────────────────────────────────

@test "build_list: private session excluded from list by default" {
  setup_private_tmux_mock ""
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" != "s:secretSession" ]]
  done
}

@test "build_list: private session windows excluded from list by default" {
  setup_private_tmux_mock ""
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" != "w:secretSession:0" ]]
  done
}

@test "build_list: non-private sessions still appear when private sessions exist" {
  setup_private_tmux_mock ""
  local US=$'\x1f'
  run build_list ""
  local has_a=0 has_b=0
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:sessionA" ]] && has_a=1
    [[ "$key" == "s:sessionB" ]] && has_b=1
  done
  [ "$has_a" -eq 1 ]
  [ "$has_b" -eq 1 ]
}

@test "build_list: private session shown when @switcher_show_private is 1" {
  setup_private_tmux_mock "1"
  local US=$'\x1f'
  run build_list ""
  local found=0
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:secretSession" ]] && found=1
  done
  [ "$found" -eq 1 ]
}

# ── Group 2: Lock icon ──────────────────────────────────────────────────────

@test "build_list: private session shows lock icon when revealed" {
  setup_private_tmux_mock "1"
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:secretSession" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"󰌾"* ]]
}

@test "build_list: non-private session does not show lock icon when revealed" {
  setup_private_tmux_mock "1"
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:sessionA" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" != *"󰌾"* ]]
}

# ── Group 3: Categorization ─────────────────────────────────────────────────

@test "build_list: active private session appears in active section when revealed" {
  setup_private_tmux_mock "1"
  local US=$'\x1f'
  run build_list ""
  # secretSession is 1h old (active) — must appear before Inactive header
  local found_secret=0 found_inactive_header=0
  for line in "${lines[@]}"; do
    local key f1
    f1=$(printf '%s' "$line" | cut -d"$US" -f1)
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$f1" == *"Inactive"* ]] && found_inactive_header=1
    if [[ "$key" == "s:secretSession" ]]; then
      found_secret=1
      # Must appear before Inactive header
      [ "$found_inactive_header" -eq 0 ]
    fi
  done
  [ "$found_secret" -eq 1 ]
}

@test "build_list: inactive private session appears in inactive section when revealed" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV_ACTIVE=$(( now - 3600 ))
  MOCK_TS_PRIV_INACTIVE=$(( now - 86400 * 4 ))
  MOCK_SHOW_PRIVATE="1"
  export MOCK_TS_PRIV_ACTIVE MOCK_TS_PRIV_INACTIVE MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV_ACTIVE"
        printf '%s|secretSession||1\n' "$MOCK_TS_PRIV_INACTIVE"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        printf 'secretSession|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        printf 'secretSession|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  # secretSession is 4 days old — must appear after Inactive header
  local found_secret=0 found_inactive_header=0
  for line in "${lines[@]}"; do
    local f1 key
    f1=$(printf '%s' "$line" | cut -d"$US" -f1)
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$f1" == *"Inactive"* ]] && found_inactive_header=1
    if [[ "$key" == "s:secretSession" ]]; then
      found_secret=1
      [ "$found_inactive_header" -eq 1 ]
    fi
  done
  [ "$found_secret" -eq 1 ]
}

# ── Group 4: Dual flags (@hidden + @private) ────────────────────────────────

@test "build_list: hidden+private session excluded when private hidden" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE=""
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV"
        printf '%s|secretSession|1|1\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        printf 'secretSession|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        printf 'secretSession|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" != "s:secretSession" ]]
  done
}

@test "build_list: hidden+private session in inactive section when revealed" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE="1"
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV"
        printf '%s|secretSession|1|1\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        printf 'secretSession|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        printf 'secretSession|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local found_secret=0 found_inactive_header=0
  for line in "${lines[@]}"; do
    local f1 key
    f1=$(printf '%s' "$line" | cut -d"$US" -f1)
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$f1" == *"Inactive"* ]] && found_inactive_header=1
    if [[ "$key" == "s:secretSession" ]]; then
      found_secret=1
      [ "$found_inactive_header" -eq 1 ]
    fi
  done
  [ "$found_secret" -eq 1 ]
}

# ── Group 5: Edge cases ─────────────────────────────────────────────────────

@test "build_list: all sessions private produces no session keys" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE=""
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|onlySession||1\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf 'onlySession|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf 'onlySession|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" != s:* ]]
  done
}

@test "build_list: POS defaults to 1 when tracked session is private and hidden" {
  setup_private_tmux_mock ""
  run build_list "secretSession"
  [[ "${lines[0]}" == "POS:1" ]]
}

@test "build_list: idx numbering skips private sessions when hidden" {
  setup_private_tmux_mock ""
  local US=$'\x1f'
  run build_list ""
  # sessionA and sessionB should get consecutive idx (1, 2) with no gap
  local idx_a="" idx_b=""
  for line in "${lines[@]}"; do
    local key f1 stripped
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    f1=$(printf '%s' "$line" | cut -d"$US" -f1)
    # Strip ANSI escapes before extracting the numeric index
    stripped=$(printf '%s' "$f1" | sed $'s/\x1b\\[[0-9;]*m//g')
    if [[ "$key" == "s:sessionA" ]]; then
      idx_a=$(printf '%s' "$stripped" | grep -o '[0-9]\+' | head -1)
    fi
    if [[ "$key" == "s:sessionB" ]]; then
      idx_b=$(printf '%s' "$stripped" | grep -o '[0-9]\+' | head -1)
    fi
  done
  [ -n "$idx_a" ]
  [ -n "$idx_b" ]
  [ "$(( idx_b - idx_a ))" -eq 1 ]
}

# ── Group 6: handle_selection ────────────────────────────────────────────────

@test "handle_selection: does not unset @private when switching to session" {
  local tmpdir
  tmpdir=$(mktemp -d)
  export tmpdir
  tmux() {
    echo "tmux $*" >> "$tmpdir/tmux-calls.log"
    case "$1" in
      switch-client) return 0 ;;
      *) return 0 ;;
    esac
  }
  export -f tmux
  run handle_selection "s:secretSession"
  # Must NOT contain any call with @private
  ! grep -q "@private" "$tmpdir/tmux-calls.log" 2>/dev/null
  rm -rf "$tmpdir"
}

# ── Group 7: Binding grep tests ─────────────────────────────────────────────

@test "fzf invocation: ctrl-x binding sets @hidden" {
  grep -q 'ctrl-x.*@hidden' "$SCRIPT"
}

@test "fzf invocation: ctrl-h binding toggles @private" {
  grep -q 'ctrl-h.*@private' "$SCRIPT"
}

@test "fzf invocation: ctrl-r binding toggles @switcher_show_private" {
  grep -q 'ctrl-r.*@switcher_show_private' "$SCRIPT"
}

@test "fzf invocation: header shows ctrl-r reveal" {
  grep -q 'ctrl-r.*reveal' "$SCRIPT"
}

@test "fzf invocation: header shows ctrl-x hide" {
  grep -q 'ctrl-x.*hide' "$SCRIPT"
}

@test "fzf invocation: header shows ctrl-h lock" {
  grep -q 'ctrl-h.*lock' "$SCRIPT"
}

@test "fzf invocation: ctrl-r binding uses become for theme switch" {
  grep -q 'ctrl-r.*become.*--run' "$SCRIPT"
}

@test "theme: Catppuccin Latte colors defined for reveal mode" {
  grep -q '#eff1f5' "$SCRIPT"
}

@test "theme: Catppuccin Mocha colors defined for default mode" {
  grep -q '#1e1e2e' "$SCRIPT"
}

@test "main block: skips @switcher_show_private reset on --run re-entry" {
  grep -q '"$1" != "--run"' "$SCRIPT"
}

# ── Group 8: @switcher_show_private reset ────────────────────────────────────

@test "main block: clears @switcher_show_private on launch" {
  grep -q 'set -gu @switcher_show_private' "$SCRIPT"
}

# ── Group 9: Private _default ────────────────────────────────────────────────

@test "build_list: private _default excluded when hidden" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE=""
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|_default||1\n' "$MOCK_TS_PRIV"
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf '_default|0|dev|zsh|/tmp|1||\n'
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf '_default|0|0|zsh|/tmp|1||\n'
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" != "s:_default" ]]
  done
}

@test "build_list: private _default shown with lock when revealed" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE="1"
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|_default||1\n' "$MOCK_TS_PRIV"
        printf '%s|sessionA||\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf '_default|0|dev|zsh|/tmp|1||\n'
        printf 'sessionA|0|dev|zsh|/tmp|1||\n'
        ;;
      "list-panes -a")
        printf '_default|0|0|zsh|/tmp|1||\n'
        printf 'sessionA|0|0|zsh|/tmp|1||\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list ""
  local found=0 field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:_default" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
  [[ "$field1" == *"󰌾"* ]]
}

# ── Group 10: Private + attention badge ──────────────────────────────────────

@test "build_list: private session with attention shows both lock and warning badge" {
  local now
  now=$(date +%s)
  MOCK_TS_PRIV=$(( now - 3600 ))
  MOCK_SHOW_PRIVATE="1"
  export MOCK_TS_PRIV MOCK_SHOW_PRIVATE
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        # secretSession is private, and its window has @claude_done set → attention
        printf '%s|secretSession||1\n' "$MOCK_TS_PRIV"
        ;;
      "list-windows -a")
        printf 'secretSession|0|dev|zsh|/tmp|1||done\n'
        ;;
      "list-panes -a")
        printf 'secretSession|0|0|zsh|/tmp|1||done\n'
        ;;
      "show-options -gv")
        [[ "$3" == "@switcher_show_private" && -n "$MOCK_SHOW_PRIVATE" ]] && printf '%s\n' "$MOCK_SHOW_PRIVATE"
        ;;
    esac
  }
  export -f tmux
  local US=$'\x1f'
  run build_list "" "1"
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "s:secretSession" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"󰌾"* ]]
  [[ "$field1" == *"⚠"* ]]
}

# ── Group 11: Two-phase load consistency ─────────────────────────────────────

@test "build_list: fast and full load produce same line count with private sessions" {
  setup_private_tmux_mock ""
  local fast_count full_count
  fast_count=$(build_list "" "1" | wc -l | tr -d ' ')
  full_count=$(build_list "" | wc -l | tr -d ' ')
  [ "$fast_count" -eq "$full_count" ]
}

# ── Group 12: Toggle-off grep ────────────────────────────────────────────────

@test "fzf invocation: ctrl-h binding contains both set and unset for @private toggle" {
  grep -q '@private 1' "$SCRIPT"
  grep -q '\-u @private' "$SCRIPT"
}
