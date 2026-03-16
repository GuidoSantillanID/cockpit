#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/../.."

# ── ghostty/config ────────────────────────────────────────────────────────────

@test "ghostty/config: term uses hyphen (xterm-256color), not equals sign" {
  run grep 'xterm=256color' "$REPO/ghostty/config"
  [ "$status" -ne 0 ]
}

# ── SETUP.md ──────────────────────────────────────────────────────────────────

@test "SETUP.md: no xterm=256color typo" {
  run grep 'xterm=256color' "$REPO/SETUP.md"
  [ "$status" -ne 0 ]
}

@test "SETUP.md: sessionizer setup references variables not brittle line numbers" {
  run grep 'lines 8' "$REPO/SETUP.md"
  [ "$status" -ne 0 ]
}

# ── guido-theme.toml ──────────────────────────────────────────────────────────

@test "guido-theme.toml: has comment explaining relationship to config.toml" {
  run grep 'config.toml' "$REPO/claude/ccline/themes/guido-theme.toml"
  [ "$status" -eq 0 ]
}

# ── README.md file map completeness ───────────────────────────────────────────

@test "README.md: all sync.sh copy_if_exists destinations are listed" {
  local sync_sh="$REPO/sync.sh"
  local readme="$REPO/README.md"
  local missing=()

  # Extract repo-relative paths from copy_if_exists calls
  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    grep -qF "$dest" "$readme" || missing+=("$dest")
  done < <(grep 'copy_if_exists' "$sync_sh" | grep -v '^#' | \
    sed -n 's|.*"\$REPO_DIR/\([^"]*\)".*|\1|p')

  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing from README.md: %s\n' "${missing[@]}"
    return 1
  fi
}
