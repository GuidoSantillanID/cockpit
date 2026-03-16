#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ ! -e "$src" ]]; then
    echo "  skipped $dest (not found: $src)"
    return
  fi
  # Skip if src is a symlink that already points into the repo (same resolved path)
  local real_src real_dest
  real_src=$(realpath "$src" 2>/dev/null || echo "$src")
  real_dest=$(realpath "$dest" 2>/dev/null || echo "$dest")
  if [[ "$real_src" == "$real_dest" ]]; then
    echo "  skipped $dest (symlink already points to cockpit)"
    return
  fi
  cp "$src" "$dest"
  echo "  updated $dest"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then

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
copy_if_exists "$HOME/shell-functions.zsh"                           "$REPO_DIR/shell-functions.zsh"
copy_if_exists "$HOME/.local/bin/tmux-session-switcher"              "$REPO_DIR/tmux/tmux-session-switcher"
copy_if_exists "$HOME/.claude/CLAUDE.md"                             "$REPO_DIR/claude/CLAUDE.md"
copy_if_exists "$HOME/.claude/skills/commit/SKILL.md"               "$REPO_DIR/claude/skills/commit/SKILL.md"
copy_if_exists "$HOME/.claude/skills/p/SKILL.md"                    "$REPO_DIR/claude/skills/p/SKILL.md"
copy_if_exists "$HOME/.claude/skills/review-pr/SKILL.md"            "$REPO_DIR/claude/skills/review-pr/SKILL.md"
copy_if_exists "$HOME/.claude/skills/test-pr/SKILL.md"              "$REPO_DIR/claude/skills/test-pr/SKILL.md"
copy_if_exists "$HOME/.claude/skills/update-docs/SKILL.md"          "$REPO_DIR/claude/skills/update-docs/SKILL.md"
copy_if_exists "$HOME/.claude/skills/update-pr-description/SKILL.md" "$REPO_DIR/claude/skills/update-pr-description/SKILL.md"
copy_if_exists "$HOME/.claude/skills/init/SKILL.md"                 "$REPO_DIR/claude/skills/init/SKILL.md"
copy_if_exists "$HOME/.config/bat/themes/Catppuccin Mocha.tmTheme"   "$REPO_DIR/bat/themes/Catppuccin Mocha.tmTheme"
copy_if_exists "$HOME/.gitconfig"                                     "$REPO_DIR/shell/gitconfig"
copy_if_exists "$HOME/.zprofile"                                      "$REPO_DIR/shell/zprofile"
copy_if_exists "$HOME/.p10k.zsh"                                      "$REPO_DIR/shell/p10k.zsh"

# Brewfile (shell/Brewfile) is NOT auto-synced — update it manually when needed:
#   brew bundle dump --file=shell/Brewfile --force

# Extract the two meaningful config lines from .zshrc (theme + plugins)
if [[ -f "$HOME/.zshrc" ]]; then
  grep -E '^(ZSH_THEME=|plugins=)' "$HOME/.zshrc" > "$REPO_DIR/shell/zshrc-config" 2>/dev/null \
    && echo "  updated $REPO_DIR/shell/zshrc-config" \
    || echo "  skipped zshrc-config (no matches)"
fi


echo ""
git -C "$REPO_DIR" diff --stat . || true

fi  # end BASH_SOURCE guard
