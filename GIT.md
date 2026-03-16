# Git Setup

Enhanced git workflow using [delta](https://github.com/dandavison/delta) as the pager. All config lives in `~/.gitconfig` (backed up at `shell/gitconfig`).

---

## Pager: delta

Every `git diff`, `git show`, `git log -p`, and `git blame` automatically flows through delta:

- Syntax highlighting via Catppuccin Mocha (bat theme at `bat/themes/Catppuccin Mocha.tmTheme`)
- Word-level diff highlighting — shows exactly which characters changed, not just which lines
- Line numbers on both sides
- File navigation with `n` / `N` — jump between changed files in long diffs
- Clickable file paths in Ghostty (OSC 8 hyperlinks — `cmd+click` to open)

---

## Aliases

| Command | Does |
|---|---|
| `git diff` | Default unified diff |
| `git diffs` | Side-by-side mode — use when terminal is wide enough |
| `git review` | Diff of the last commit — quick check of what Claude just changed |
| `git gl` | Oneline log with relative time and branch decorations |
| `git glh` | Same as `gl` but includes short commit hash |
| `git glp` | Patch log — full diff for every commit, paginated through delta |
| `git pushpr <branch>` | Push HEAD to a named remote branch |

---

## Diff quality settings

```ini
[diff]
    algorithm = histogram   # better diffs for moved/refactored code
    colorMoved = default    # highlights moved code blocks distinctly

[merge]
    conflictstyle = zdiff3  # shows common ancestor in conflict markers, removes redundant lines

[rerere]
    enabled = true          # remembers conflict resolutions — reuses them on rebase
```

**`histogram`** produces cleaner diffs when code is moved or refactored — fewer false "changed" lines.

**`zdiff3`** gives the most informative merge conflict markers. Compared to the default `merge` style, it adds the common ancestor (what the code looked like before both branches changed it) and removes lines that are identical in all three versions.

**`rerere`** (Reuse Recorded Resolution) memorises how you resolved a conflict and reapplies it automatically if the same conflict appears again — useful when rebasing a long-lived branch repeatedly.

---

## Navigation in diffs

When paging through a `git diff` or `git log -p`:

| Key | Action |
|---|---|
| `n` | Jump to next changed file |
| `N` | Jump to previous changed file |
| `q` | Quit |
| `space` | Page down |
| `b` | Page up |

---

## Catppuccin Mocha color palette

The diff backgrounds use Catppuccin Mocha hex values directly — not delta's defaults:

| Context | Color | Hex |
|---|---|---|
| Added line background | Muted teal | `#394545` |
| Removed line background | Muted plum | `#493447` |
| Added word emphasis | Lighter teal | `#4e6356` |
| Removed word emphasis | Lighter plum | `#694559` |
| Line number (changed) | Green / Red | `#a6e3a1` / `#f38ba8` |
| Text on diff lines | Text | `#cdd6f4` |

`syntax-theme = Catppuccin Mocha` (bat theme) handles keyword/string/comment colors within the diff.

---

## Branch management

```ini
[branch]
    sort = -committerdate   # git branch lists most recently used branches first

[push]
    autoSetupRemote = true  # first push auto-sets upstream, no -u needed

[fetch]
    prune = true            # removes stale remote-tracking branches on every fetch

[rebase]
    autoStash = true        # stashes uncommitted changes before rebase, restores after
```
