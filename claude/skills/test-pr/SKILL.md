---
name: test-pr
description: Generates a prioritized testing checklist for a PR or branch. Analyzes monorepo structure, detects frameworks/infra, and produces a phase-by-phase verification workflow.
metadata:
  author: guido
  version: "1.0.0"
  argument-hint: "[pr-number | branch-name]"
user-invocable: true
---

# PR Testing Checklist Generator

Generate a prioritized, actionable testing checklist for a PR or local branch. Follow steps exactly.

**Do NOT use the Task tool (subagents). Process everything inline.**

## Step 1: Parse Input & Detect Scope

Input mode from skill arguments:
- **Number** → PR mode (use `gh pr view` to get head branch, then diff)
- **String** → Branch mode (that branch vs main)
- **No arg** → Branch mode (detect current branch vs main)

Base branch: `main` (fallback: `master`).

## Step 2: Detect Project Structure

Run **in parallel**:
1. Read root `package.json` — identify package manager, scripts, engine requirements
2. Read `pnpm-workspace.yaml` / `lerna.json` / root `workspaces` field — detect monorepo structure
3. Read `turbo.jsonc` or `turbo.json` or `nx.json` — detect build orchestrator
4. Read `.nvmrc` or `.node-version` or `engines.node` — detect Node version requirement

### Discover workspaces

For each workspace directory found:
1. Read its `package.json`
2. Record:
   - **Name** and **path**
   - **Available scripts**: `dev`, `build`, `lint`, `typecheck`, `test`, and any custom scripts
   - **Framework**: detect from deps (next → Next.js, vite → Vite, storybook → Storybook, @docusaurus → Docusaurus, prisma → Prisma, vitest → Vitest, jest → Jest)
   - **Dev server port**: infer from scripts (e.g., `-p 3000`, `-p 6006`)
   - **Key deps**: auth libs, DB clients, API frameworks, UI libraries

## Step 3: Detect Infrastructure

Check for existence of these files/dirs (use Glob, **in parallel**):

| File/Pattern | Capability |
|---|---|
| `Dockerfile` | Docker build |
| `.github/workflows/*.yml` | CI pipelines |
| `**/prisma/schema.prisma` | Database (Prisma) |
| `**/drizzle.config.*` | Database (Drizzle) |
| `.husky/pre-commit` | Pre-commit hooks |
| `.lintstagedrc*` | Lint-staged config |
| `.prettierrc*` or `prettier.config.*` | Prettier |
| `**/eslint.config.*` or `**/.eslintrc.*` | ESLint |
| `.env.example` or `**/.env.example` | Environment variables |
| `**/vitest.config.*` or `**/jest.config.*` | Test runner |
| `**/bundle-analyzer*` or `ANALYZE` in next.config | Bundle analyzer |
| `scripts/*.ts` or `scripts/*.js` | Custom scripts |

For each CI workflow found, read it to identify:
- Job names and what they run
- Whether it has caching, artifacts, deploy steps
- Which events trigger it (push, PR, manual)

## Step 4: Diff Analysis

If on a branch (not main):

```bash
git diff main...HEAD --numstat -- . ':!pnpm-lock.yaml' ':!package-lock.json' ':!yarn.lock'
```

From the numstat, compute:
1. **Touched workspaces** — which `apps/` and `packages/` dirs have changes
2. **High-change files** — files with 50+ lines changed (potential risk)
3. **New files** — additions that need first-time verification
4. **Deleted files** — check for broken imports/references
5. **Binary/asset changes** — need manual visual check
6. **Config changes** — CI, Docker, tsconfig, eslint, package.json (infra risk)

Also run:
```bash
git log --oneline main..HEAD
```
To get commit count and commit messages (useful for understanding intent).

## Step 5: Generate Checklist

Build the checklist dynamically based on what was detected. Only include sections relevant to this project.

### Section generation rules

| Condition | Include section |
|---|---|
| Always | Environment Setup |
| Always | Quality Gates |
| Has `build` script | Build |
| Has apps with `dev` script | Runtime Verification (per app) |
| Has Prisma/Drizzle | Database |
| Has `.husky/` or `.lintstagedrc` | Pre-commit Hooks |
| Has Prettier config | Formatting |
| Has ESLint config | Linting |
| Has bundle analyzer | Bundle Analysis |
| Has Dockerfile | Docker |
| Has CI workflows | CI Pipeline |
| Has diff | Risk Areas |
| Always | Priority Order |

### Per-app runtime checks

For each app with a `dev` script, generate specific checks based on framework:

**Next.js apps:**
- Dev server starts
- Home page loads at detected port
- API routes respond (list any `app/api/` or `pages/api/` dirs found)
- Error boundary works (if `error.tsx` exists)
- Loading states show (if `loading.tsx` exists)
- Auth flow works (if auth lib detected)

**Storybook apps:**
- Dev server starts at detected port
- Stories render without console errors
- If diff touches UI components → list specific stories to spot-check
- If assets changed → verify they load (images, fonts, audio)

**Docusaurus apps:**
- Dev server starts
- Pages render, navigation works
- Search works (if search plugin detected)

**Vite apps:**
- Dev server starts
- App renders at detected port

**Generic apps:**
- Dev server starts (if `dev` script exists)
- Main functionality works

### Risk area generation (from diff)

Group changed files by workspace. For each workspace with changes:
- List high-change files (50+ lines) with line counts
- Flag removed dependencies (check deleted lines in package.json for dep removals)
- Flag config changes (tsconfig, eslint, next.config, etc.)
- Flag binary/asset changes needing visual verification
- If UI components changed → list them for visual spot-check

## Step 6: Output Mode

Before writing, ask the user using the AskUserQuestion tool:
- Question: "How should I output the testing checklist?"
- Options:
  1. **Save to file** — Write to `.reviews/` directory
  2. **Print here** — Output inline in chat

If **Save to file**:
- PR mode: `.reviews/test-pr-<number>.md`
- Branch mode: `.reviews/test-<branch-name>.md` (replace `/` with `-`)

## Step 7: Write Output

### Template — use this exact format

```markdown
# Testing Checklist: <branch-name or PR #N>
> Generated on <YYYY-MM-DD>
> Companion to review guide: run `/review-pr` first to understand WHAT changed.

## Overview
| Field | Value |
|---|---|
| Branch | `head` -> `base` |
| Commits | N |
| Workspaces | N total, M touched |
| Frameworks | Next.js, Storybook, ... |
| Infra | Docker, CI, Prisma, ... |

## Environment Setup
- [ ] Node version: `vXX` (check `.nvmrc`)
- [ ] Package manager: `pnpm@X.Y.Z` (check `packageManager` field)
- [ ] Clean install: `rm -rf node_modules apps/*/node_modules packages/*/node_modules && pnpm install`
- [ ] Env files: copy `.env.example` to `.env.local` (if exists)
- [ ] Database: `pnpm db:sync && pnpm db:seed` (if Prisma detected)

## Phase 1: Quality Gates
> Automated checks — these mirror CI. If these pass, 80% of issues are caught.

- [ ] **Lint**: `pnpm lint` — passes all workspaces
- [ ] **Typecheck**: `pnpm typecheck` — passes all workspaces
- [ ] **Test**: `pnpm test` — passes all workspaces
- [ ] **Workspace conventions**: `pnpm check:workspaces` (if script exists)

## Phase 2: Build
- [ ] **Full build**: `pnpm build` — all workspaces succeed
- [ ] **Storybook build**: `pnpm build-storybook` (if Storybook detected)
  - Verify output size is reasonable
  - Check `storybook-static/` is produced

## Phase 3: Runtime Verification

### <app-name> (<framework>)
- [ ] Dev server starts: `pnpm --filter <name> dev`
- [ ] <framework-specific checks...>
- [ ] Changed components render correctly: <list from diff>

### <next-app...>
...

## Phase 4: Tooling
- [ ] **Pre-commit hook**: stage a file, commit → verify lint-staged runs
- [ ] **Prettier**: disorder imports in a .tsx → `pnpm format` → verify sorted
- [ ] **ESLint**: add unused variable → `pnpm lint` → verify caught
- [ ] **Bundle analyzer**: `ANALYZE=true pnpm --filter web build` (if detected)

## Phase 5: Docker
- [ ] **Build**: `docker build --build-arg NPM_TOKEN=<token> -t <name> .`
- [ ] **Run**: `docker run -p 3000:3000 <name>` → app starts
- [ ] **Verify**: http://localhost:3000 responds

## Phase 6: CI Pipeline
- [ ] Push branch and open PR against `main`
- [ ] All CI jobs pass: <list job names from workflow>
- [ ] <Deploy/preview jobs if applicable>

## Risk Areas
> Files with high change counts or structural changes. Verify these manually.

### <workspace-name>
- [ ] `path/to/file.tsx` — N+ / M- lines — <what to check>
- [ ] <removed-dep> removed from package.json — verify no broken imports
- [ ] <asset-change> — verify visually

## Priority Order (if time-limited)
1. **Phase 1** — Quality gates catch 80% of issues
2. **Phase 2** — Build verification catches dep/config problems
3. **Phase 3** — Runtime check for <highest-risk app>
4. **Phase 5/6** — Docker + CI for production readiness
```

### Format rules

- Every checklist item is a GitHub-flavored markdown checkbox: `- [ ]`
- Every item has a **command** (in backticks) and **what to verify** (plain text after em-dash)
- Sections are conditional — omit entirely if not applicable (no empty sections, no "N/A")
- Risk areas sorted by change size (largest first)
- Priority order is always last, always present, max 5 items

### Large PR handling (50+ files changed)
- Add warning at top: "Large PR — focus on Phase 1 + Risk Areas first"
- In Risk Areas, group files by workspace instead of listing individually
- Cap risk items at 15 most impactful

### No-diff mode (running on main or clean branch)
- Skip Risk Areas section entirely
- Skip "M touched" from overview
- Generate baseline checklist for full project health check

## Step 8: Report to User

Print brief summary:
- File path (if saved) or note printed inline
- Workspaces detected / touched
- Phases generated
- Top 3 risk areas
- Suggest running `/review-pr` first if they haven't already

## Tips for Best Results

1. **Pair with `/review-pr`** — Review guide shows WHAT changed (file tiers, AI red flags). Test checklist shows HOW to verify it works. Run review first.
2. **Focus on touched workspaces** — When time is limited, skip apps/packages with zero diff.
3. **Visual verification** — For UI component changes, always open Storybook and spot-check the specific stories.
4. **Regression check** — When deps are removed from package.json, verify no component imports them.
5. **Environment parity** — Ensure local Node/pnpm versions match `.nvmrc` and `packageManager` before testing. Version mismatches cause false failures.
