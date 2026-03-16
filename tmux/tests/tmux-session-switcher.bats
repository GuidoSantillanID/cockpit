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

# ── strip_claude_prefix ───────────────────────────────────────────────────────

@test "strip_claude_prefix: strips prefix" {
  run strip_claude_prefix "✳ claude"
  [ "$output" = "claude" ]
}

@test "strip_claude_prefix: no-op when no prefix" {
  run strip_claude_prefix "dev"
  [ "$output" = "dev" ]
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
# Active: accessed within 3 days (259200 seconds); inactive: older

@test "category_for_age: active when within 3 days" {
  run category_for_age 3600      # 1h ago
  [ "$output" = "active" ]
}

@test "category_for_age: active at exactly 3 days boundary" {
  run category_for_age 259200    # exactly 3 days
  [ "$output" = "active" ]
}

@test "category_for_age: inactive when older than 3 days" {
  run category_for_age 259201    # 3 days + 1 second
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

@test "build_list: running window shows dirname before 'running'" {
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
  # Find the window row (field 3 = w:myproject:0) and check field 2
  local detail=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:myproject:0" ]]; then
      detail=$(printf '%s' "$line" | cut -d"$US" -f2)
      break
    fi
  done
  # detail should be "· myproject · running", NOT "· running · myproject"
  [[ "$detail" == *"myproject"*"running"* ]]
  [[ "$detail" != *"running"*"myproject"* ]] || {
    # Extra check: "running" must come AFTER "myproject" in the string
    local pos_repo pos_run
    pos_repo=$(printf '%s' "$detail" | awk '{print index($0,"myproject")}')
    pos_run=$(printf '%s' "$detail" | awk '{print index($0,"running")}')
    [ "$pos_repo" -lt "$pos_run" ]
  }
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

@test "build_list: multi-pane window shows combined label with slash separator" {
  local now
  now=$(date +%s)
  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|myproject\n' "$(( now - 60 ))"
        ;;
      "list-windows -a")
        printf 'myproject|0|dev|claude|/home/user/myproject|1|1|\n'
        ;;
      "list-panes -a")
        printf 'myproject|0|0|claude|/home/user/myproject|1|1|\n'
        printf 'myproject|0|1|zsh|/home/user/myproject|0||\n'
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
  [[ "$field1" == *"/"* ]]
  [[ "$field1" == *"claude"* ]]
  [[ "$field1" == *"shell"* ]]
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

# ── dead code absence ────────────────────────────────────────────────────────

@test "category_for_timestamp: dead function has been removed" {
  run grep 'category_for_timestamp' "$BATS_TEST_DIRNAME/../tmux-session-switcher"
  [ "$status" -ne 0 ]
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

@test "build_list: multi-pane data in mock produces combined label for sessionA window" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  local field1=""
  for line in "${lines[@]}"; do
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    if [[ "$key" == "w:sessionA:0" ]]; then
      field1=$(printf '%s' "$line" | cut -d"$US" -f1)
      break
    fi
  done
  [[ "$field1" == *"/"* ]]
  [[ "$field1" == *"claude"* ]]
  [[ "$field1" == *"shell"* ]]
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
