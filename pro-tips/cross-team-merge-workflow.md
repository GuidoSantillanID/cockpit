# Cross-Team Merge Workflow (Monorepo)

> **TL;DR:** Each engineer creates an integration branch, merges main, resolves only their component, pushes. One person does the final merge and runs `git checkout origin/<integration-branch> -- components/<name>/` per component to apply all resolutions instantly. No coordination calls, no patches, fully async.

## The Problem

In a monorepo, a long-lived feature branch diverges from main. Merging produces conflicts across multiple components (web, api, core, sdk) owned by different engineers in different timezones. Git merge is atomic — all conflicts must be resolved in one commit, on one machine.

## The Solution: Integration Branch + Checkout

Each engineer resolves their component's conflicts on a separate **integration branch**. When it's time to do the actual merge, one person applies all resolutions with a single command per component.

## How It Works

### Phase 1 — Each engineer resolves their component (async, any machine, any time)

```bash
# 1. Create an integration branch from the feature branch
git checkout -b <ticket>-integration-<component> origin/<feature-branch>

# 2. Merge main (all conflicts appear)
git merge origin/main

# 3. Resolve ONLY your component's conflicts
#    (e.g., only files in components/web/)

# 4. For everything else, keep the feature branch version
git checkout --ours -- components/api/ components/core/ # etc
git checkout --ours -- .github/ deploy/ charts/          # misc files

# 5. Stage and commit
git add -A
git commit -m "Integration: <component> conflicts resolved"
git push -u origin <ticket>-integration-<component>
```

Repeat for each component owner. Everyone works independently.

### Phase 2 — Final merge (one person collects all resolutions)

```bash
# 1. Start from the feature branch
git checkout <feature-branch>
git reset --hard origin/<feature-branch>  # ensure clean state

# 2. Merge main (all conflicts appear again)
git merge origin/main

# 3. Apply each component's resolution (one command each)
git checkout origin/<ticket>-integration-web -- components/web/
git checkout origin/<ticket>-integration-api -- components/api/
git checkout origin/<ticket>-integration-core -- components/core/
# ...repeat for each integration branch

# 4. Check what's left unresolved
git diff --name-only --diff-filter=U
# (should be minimal — only files no one claimed, like .github/, deploy/)

# 5. Resolve remaining misc conflicts, commit, push
git add -A
git commit -m "Merge main into <feature-branch>: resolve all conflicts"
git push
```

## Why This Works

- `git checkout origin/<branch> -- <path>` copies resolved files **and stages them**, instantly marking those conflicts as resolved
- Each integration branch merged the **same main**, so the resolutions are exact matches
- No patches, no file sharing, no coordination calls needed
- Each engineer works on their own machine, own schedule

## Rules

1. **Everyone must merge the same `origin/main`** — if main moves, integration branches become stale. Coordinate timing or freeze main.
2. **Don't resolve other people's components** — use `git checkout --ours` for everything outside your scope.
3. **Push your integration branch** — others need `origin/<branch>` access for the checkout step.
4. **Keep integration branches until the final merge is done** — then delete them.

## Scaling

| People | Setup |
|--------|-------|
| 2 | One integration branch, other person does final merge + resolves the rest directly |
| 3+ | One integration branch per component, anyone does the final merge |
| N components, 1 person each | Each creates integration branch, last person applies all + commits |

## Example: GP-1167

```
Feature branch: GP-1167-Clean-Up-the-Dotnet-Controllers-and-APIs
263 conflicting files: web (124), api (43), core (74), sdk (12), misc (10)

Web engineer created: GP-1167-integration (resolved 124 web conflicts)
Backend engineer ran:
  git merge origin/main
  git checkout origin/GP-1167-integration -- components/web/
  → 124 web conflicts resolved instantly
  → Only 139 non-web conflicts remained
```

## Common Mistakes

| Mistake | Why it fails | Fix |
|---------|-------------|-----|
| `git checkout --ours .` then commit ALL | Git considers main fully merged — can't re-merge | Use `--ours` only for components you DON'T own |
| Skip `git merge origin/main` in Phase 2 | No merge = no conflicts = checkout just overwrites files | Always merge first, then apply resolutions |
| Integration branches merge different `origin/main` commits | Resolutions won't match the new merge's conflicts | Coordinate timing, or re-create stale integration branches |
| Resolving conflicts in files outside your component | Other engineer's resolution overwrites yours in Phase 2 | Stick to your component, `--ours` everything else |
