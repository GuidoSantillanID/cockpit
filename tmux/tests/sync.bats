#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../../sync.sh"

setup() {
  TMPDIR=$(mktemp -d)
  export TMPDIR
  # Source sync.sh to get copy_if_exists; BASH_SOURCE guard skips the main body.
  # Temporarily disable errexit so sync.sh's set -e doesn't affect test isolation.
  set +e
  # shellcheck disable=SC1090
  source "$SCRIPT"
  set -e
}

teardown() {
  rm -rf "$TMPDIR"
}

# ── copy_if_exists ─────────────────────────────────────────────────────────────

@test "copy_if_exists: copies file and prints updated" {
  local src="$TMPDIR/src.txt"
  local dest="$TMPDIR/dest.txt"
  echo "content" > "$src"

  run copy_if_exists "$src" "$dest"

  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
  [ -f "$dest" ]
}

@test "copy_if_exists: skips when source does not exist" {
  local src="$TMPDIR/nonexistent.txt"
  local dest="$TMPDIR/dest.txt"

  run copy_if_exists "$src" "$dest"

  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
  [ ! -f "$dest" ]
}

@test "copy_if_exists: skips when source is symlink pointing to dest" {
  local dest="$TMPDIR/dest.txt"
  echo "content" > "$dest"
  local src="$TMPDIR/src-link"
  ln -s "$dest" "$src"

  run copy_if_exists "$src" "$dest"

  [ "$status" -eq 0 ]
  [[ "$output" == *"symlink"* ]]
}

@test "copy_if_exists: succeeds when dest parent dir exists" {
  local srcdir="$TMPDIR/srcdir"
  local destdir="$TMPDIR/destdir"
  mkdir -p "$srcdir" "$destdir"
  local src="$srcdir/file.txt"
  local dest="$destdir/file.txt"
  echo "content" > "$src"

  run copy_if_exists "$src" "$dest"

  [ "$status" -eq 0 ]
  [[ "$output" == *"updated"* ]]
  [ -f "$dest" ]
}
