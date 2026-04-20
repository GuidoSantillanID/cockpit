# cockpit

> **STOP. Before editing any file in this repo: is it a synced file?**
> Check the table below. If yes — **do not edit it here**. Edit the live file on the local machine instead. `sync.sh` overwrites repo copies — edits here will be lost and will confuse the source of truth.
> This rule has been violated before. It must not happen again.

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

## Writing docs with factual claims

Source-first: fetch and read the primary source before writing any number,
percentage, benchmark score, model name, or date. Cite inline at write time —
never write a claim and look up the source later.

- Every number needs a `[source](url)` in the same line, same edit.
- If the source isn't at hand, write `[CITE]` as a placeholder and stop.
- Never write from memory. If it feels right but you haven't checked, check first.
- Before committing: every number in the diff has a URL next to it, or it doesn't ship.

## Verify

```bash
bats tmux/tests/tmux-session-switcher.bats
bats tmux/tests/tmux-pane-toggle.bats
```

Shell/config only — no lint or typecheck.
