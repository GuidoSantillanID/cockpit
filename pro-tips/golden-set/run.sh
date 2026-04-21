#!/usr/bin/env bash
# Set up a throwaway git repo with a golden-set fixture applied, ready
# for the review-multi-agent skill to be invoked against it.
#
# Usage: ./run.sh <fixture-name>

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

usage() {
  echo "Usage: $0 <fixture-name>" >&2
  echo "" >&2
  echo "Available fixtures:" >&2
  if [[ -d "$FIXTURES_DIR" ]]; then
    for d in "$FIXTURES_DIR"/*/; do
      [[ -d "$d" ]] && echo "  $(basename "$d")" >&2
    done
  else
    echo "  (none yet)" >&2
  fi
  exit 1
}

[[ $# -eq 1 ]] || usage

FIXTURE=$1
FIXTURE_DIR="$FIXTURES_DIR/$FIXTURE"

if [[ ! -d "$FIXTURE_DIR" ]]; then
  echo "Fixture not found: $FIXTURE" >&2
  usage
fi

if [[ ! -d "$FIXTURE_DIR/setup" ]]; then
  echo "Fixture missing setup/ directory: $FIXTURE" >&2
  exit 1
fi

if [[ ! -f "$FIXTURE_DIR/diff.patch" ]]; then
  echo "Fixture missing diff.patch: $FIXTURE" >&2
  exit 1
fi

if [[ ! -f "$FIXTURE_DIR/expected.json" ]]; then
  echo "Fixture missing expected.json: $FIXTURE" >&2
  exit 1
fi

WORK=$(mktemp -d -t pr-review-fixture.XXXXXX)
cd "$WORK"

git init -q -b main
git config user.email "fixture@test.local"
git config user.name "Fixture"

# Copy everything under setup/ into the work dir (preserving structure).
cp -R "$FIXTURE_DIR/setup/." ./

git add -A
git commit -q -m "baseline (before PR)"

# Apply the PR diff.
if ! git apply "$FIXTURE_DIR/diff.patch"; then
  echo "Failed to apply diff.patch" >&2
  echo "  Fixture: $FIXTURE" >&2
  echo "  Work dir: $WORK" >&2
  exit 1
fi

git add -A
git commit -q -m "PR under review: introduces bug"

echo ""
echo "Fixture '$FIXTURE' ready at:"
echo "  $WORK"
echo ""
echo "Description:"
if command -v jq >/dev/null; then
  jq -r '.description' "$FIXTURE_DIR/expected.json" | sed 's/^/  /'
else
  echo "  (install jq to see description inline; otherwise cat expected.json)"
fi
echo ""
echo "Next steps:"
echo "  cd $WORK"
echo "  # then in a new Claude Code session:"
echo "  #   /review-multi-agent"
echo ""
echo "Compare output to expected findings:"
echo "  cat $FIXTURE_DIR/expected.json"
