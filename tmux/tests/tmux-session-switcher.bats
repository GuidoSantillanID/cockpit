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

# ── category_for_timestamp ────────────────────────────────────────────────────
# Signature: category_for_timestamp <timestamp> <today_start> <yesterday_start>

@test "category_for_timestamp: today" {
  local now today_start yesterday_start
  now=$(date +%s)
  today_start=$(date -v0H -v0M -v0S +%s)
  yesterday_start=$(date -v-1d -v0H -v0M -v0S +%s)
  run category_for_timestamp "$now" "$today_start" "$yesterday_start"
  [ "$output" = "today" ]
}

@test "category_for_timestamp: yesterday" {
  local today_start yesterday_start ts
  today_start=$(date -v0H -v0M -v0S +%s)
  yesterday_start=$(date -v-1d -v0H -v0M -v0S +%s)
  ts=$(( yesterday_start + 3600 ))  # 1h after start of yesterday
  run category_for_timestamp "$ts" "$today_start" "$yesterday_start"
  [ "$output" = "yesterday" ]
}

@test "category_for_timestamp: older" {
  local today_start yesterday_start ts
  today_start=$(date -v0H -v0M -v0S +%s)
  yesterday_start=$(date -v-1d -v0H -v0M -v0S +%s)
  ts=$(( yesterday_start - 86400 ))  # 2 days ago
  run category_for_timestamp "$ts" "$today_start" "$yesterday_start"
  [ "$output" = "older" ]
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
#   session A: last_attached = today (recent)
#   session B: last_attached = 2 days ago (older)
# Both sessions have one window each.
setup_tmux_mock() {
  local now today_start
  now=$(date +%s)
  today_start=$(date -v0H -v0M -v0S +%s)
  # Use globals (not local) + export so they survive into run's subshell
  MOCK_TS_TODAY=$(( today_start + 3600 ))    # today, 1h after midnight
  MOCK_TS_OLDER=$(( today_start - 86400 * 2 ))  # 2 days ago
  export MOCK_TS_TODAY MOCK_TS_OLDER

  tmux() {
    case "$1 $2" in
      "list-sessions -F")
        printf '%s|sessionA\n%s|sessionB\n' "$MOCK_TS_TODAY" "$MOCK_TS_OLDER"
        ;;
      "list-windows -a")
        printf 'sessionA|0|dev|zsh|/home/user/projectA|1||\n'
        printf 'sessionB|0|dev|zsh|/home/user/projectB|1||\n'
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

@test "build_list: sessions sorted most-recent first" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # sessionA (today) should appear before sessionB (older) in output
  local pos_a pos_b i=0
  for line in "${lines[@]}"; do
    i=$(( i + 1 ))
    local key
    key=$(printf '%s' "$line" | cut -d"$US" -f3)
    [[ "$key" == "s:sessionA" ]] && pos_a=$i
    [[ "$key" == "s:sessionB" ]] && pos_b=$i
  done
  [ -n "$pos_a" ]
  [ -n "$pos_b" ]
  [ "$pos_a" -lt "$pos_b" ]
}

@test "build_list: category header before older session" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # Find line before sessionB — should be an Older header (empty field 3)
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

@test "build_list: no category header for today sessions" {
  setup_tmux_mock
  local US=$'\x1f'
  run build_list ""
  # First non-empty line with content should be sessionA (no header before it)
  local first_key=""
  for line in "${lines[@]}"; do
    [[ -z "$line" ]] && continue
    first_key=$(printf '%s' "$line" | cut -d"$US" -f3)
    break
  done
  [ "$first_key" = "s:sessionA" ]
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
