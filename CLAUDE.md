# cockpit

Backup of personal Ghostty + tmux + Claude Code workflow configs. **Not the source of truth** — files live on the local machine; this repo is a copy.

## File layout

Two kinds of files:

| Kind | Examples | Edit where? |
|------|----------|-------------|
| **Synced** — live on machine, copied here by `sync.sh` | `tmux/tmux.conf`, `ghostty/config`, `claude/settings.json`, `shell/gitconfig` | Edit the live file, then run `./sync.sh` |
| **Native** — live in this repo, not copied from anywhere | `tmux/tests/`, `sync.sh`, `CLAUDE.md`, `SETUP.md` | Edit directly in the repo |

## Workflow

**CRITICAL: For synced files, never edit the repo copy directly. `sync.sh` overwrites them — direct edits will be lost.**

- Synced file: edit live → test → `./sync.sh` → commit.
- **One modification rule**: only edit the source of truth (the live file). Never modify both the live file and the repo copy — `sync.sh` handles the copy.
- New synced file: add a `copy_if_exists` line to `sync.sh`.
- Brewfile: not auto-synced. Update manually: `brew bundle dump --file=shell/Brewfile --force`

## Key wiring

`claude/settings.json` Stop/Notification hooks set `@claude_done 1` on the active tmux window. Two hooks in `tmux.conf` (`after-select-window`, `client-session-changed`) clear it. Both sides must stay in sync — this drives the green `●` tab indicator. Full detail in `SETUP.md`.

## Verify

```bash
bats tmux/tests/tmux-session-switcher.bats
bats tmux/tests/tmux-pane-toggle.bats
```

Shell/config only — no lint or typecheck.
