# Multi-Pane Focus Toggle

Replace hardcoded pane-2 references in `prefix+t` and `prefix+e` with a tracked `@secondary` variable, enabling the same toggle UX with any number of panes.

## Core Concept

Pane 1 = main. `@secondary` (window-level tmux user variable) stores the pane ID of the active secondary pane. Toggle bindings operate on main <-> `@secondary`.

## @secondary Management

**Hook:** `after-select-pane` — when the focused pane is not pane 1, set `@secondary` to that pane's ID.

**Fallback:** If `@secondary` points to a dead pane (or is unset), default to the highest-index pane in the window.

**Initial state:** First split auto-sets `@secondary` via the hook (new pane gets focus, triggers hook).

## prefix+t (Zoomed Toggle)

| State | Action |
|---|---|
| 1 pane | Split right 30%, zoom new pane |
| Unzoomed, any pane count | Zoom current pane |
| Zoomed on pane 1 | Switch to `@secondary`, stay zoomed |
| Zoomed on `@secondary` | Switch to pane 1, stay zoomed |
| Zoomed on other pane | Switch to pane 1, stay zoomed |

## prefix+e (Side-by-Side Toggle)

| State | Action |
|---|---|
| 1 pane | Split right 30%, focus new pane (no zoom) |
| Zoomed | Unzoom, focus `@secondary` |
| Unzoomed | Select pane 1, zoom (hide all extras) |

## Status Bar Badge

Gate changes from `#{window_panes} == 2` to `#{window_panes} >= 2`. Meanings:

- **SIDE** — unzoomed, 2+ panes visible
- **TERM** — zoomed on a non-main pane (pane index != 1)
- **HIDDEN** — zoomed on pane 1 (extras hidden behind zoom)

The pane identity check changes from `#{pane_index} == 1` to checking whether the current pane is pane 1 (main) or not.

## What Doesn't Change

- **Auto-resize hook** — stays gated on `#{window_panes} == 2`, unchanged
- **Pane creation/layout** — not managed by these bindings; user creates panes manually
- **`after-split-window` hook** — Dracula bg styling already uses `pane_index > 1`, works as-is
- **`prefix+q`** — tmux default `display-panes`, unchanged (but naturally feeds into `@secondary` via the hook when you select a pane)

## Implementation Scope

All changes in `tmux.conf` (synced file — edit live, then `sync.sh`):

1. Extend `after-select-pane` hook to set `@secondary` on the window when focused pane is not pane 1
2. Rewrite `bind t` to read `@secondary` and use it instead of hardcoded pane indices
3. Rewrite `bind e` to read `@secondary` and use it instead of hardcoded pane indices
4. Update `status-right` badge: gate `>= 2`, identity check based on pane index 1 vs not-1
5. Update bats tests to cover 2-pane and 3+-pane scenarios

## Open Questions

None.
