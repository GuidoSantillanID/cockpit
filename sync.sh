#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ -e "$src" ]]; then
    cp "$src" "$dest"
    echo "  updated $dest"
  else
    echo "  skipped $dest (not found: $src)"
  fi
}

echo "Updating config backups from local machine..."
echo ""

copy_if_exists "$HOME/.config/ghostty/config"                       "$REPO_DIR/ghostty/config"
copy_if_exists "$HOME/.tmux.conf"                                    "$REPO_DIR/tmux/tmux.conf"
copy_if_exists "$HOME/.config/tmux/tmux-which-key.yaml"             "$REPO_DIR/tmux/tmux-which-key.yaml"
copy_if_exists "$HOME/.local/bin/tmux-sessionizer"                  "$REPO_DIR/tmux/tmux-sessionizer"
copy_if_exists "$HOME/.claude/settings.json"                        "$REPO_DIR/claude/settings.json"
copy_if_exists "$HOME/.claude/ccline/config.toml"                   "$REPO_DIR/claude/ccline/config.toml"
copy_if_exists "$HOME/.claude/ccline/models.toml"                   "$REPO_DIR/claude/ccline/models.toml"
copy_if_exists "$HOME/.claude/ccline/themes/guido-theme.toml"       "$REPO_DIR/claude/ccline/themes/guido-theme.toml"
copy_if_exists "$HOME/shell-functions.zsh"                          "$REPO_DIR/shell-functions.zsh"

echo ""
git -C "$REPO_DIR" diff --stat . || true
