# cockpit

Backup of personal Ghostty + tmux + Claude Code workflow configs. **Not the source of truth** — files live on the local machine; this repo is a copy.

## Workflow

- To update: edit the live file → test it → `./sync.sh` → commit. Never edit files in this repo directly — `sync.sh` overwrites them.
- New file to track: add a `copy_if_exists` line to `sync.sh`.
- Brewfile: not auto-synced. Update manually: `brew bundle dump --file=shell/Brewfile --force`

## Key wiring

`claude/settings.json` Stop/Notification hooks set `@claude_done 1` on the active tmux window. Two hooks in `tmux.conf` (`after-select-window`, `client-session-changed`) clear it. Both sides must stay in sync — this drives the green `●` tab indicator. Full detail in `SETUP.md`.

## Verify

```bash
bats tmux/tests/tmux-session-switcher.bats
```

Shell/config only — no lint or typecheck.
