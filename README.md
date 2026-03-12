# cockpit

Backup of personal config files for the Ghostty + tmux + Claude Code agentic coding workflow.

**This is a backup repo — not a source of truth for installation.** These files are copies of what lives on the local machine. To update them, run `./sync.sh`.

See [SETUP.md](SETUP.md) for the full workflow walkthrough and how the pieces connect.

## File map

| File | Local path |
|---|---|
| `ghostty/config` | `~/.config/ghostty/config` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `tmux/tmux-which-key.yaml` | `~/.config/tmux/tmux-which-key.yaml` |
| `tmux/tmux-sessionizer` | `~/.local/bin/tmux-sessionizer` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/ccline/config.toml` | `~/.claude/ccline/config.toml` |
| `claude/ccline/models.toml` | `~/.claude/ccline/models.toml` |
| `claude/ccline/themes/guido-theme.toml` | `~/.claude/ccline/themes/guido-theme.toml` |
| `shell-functions.zsh` | `~/shell-functions.zsh` |

## Syncing

```bash
./sync.sh
```

Copies all files from their local paths into this repo. Review the diff, then commit.

## Stack

- **[Ghostty](https://ghostty.org)** — terminal
- **[tmux](https://github.com/tmux/tmux)** + Catppuccin + tpm — session manager
- **[Claude Code](https://claude.ai/code)** — AI coding agent
- **[wt](https://github.com/GuidoSantillanID/wt)** — git worktree lifecycle tool
- **[ccline](https://github.com/lukepaolo/ccline)** — Claude Code status line
