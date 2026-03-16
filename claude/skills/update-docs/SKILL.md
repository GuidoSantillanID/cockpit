---
name: update-docs
description: Propagates codebase changes to relevant documentation artifacts. Analyzes PR/branch diff, discovers affected docs, and proposes targeted updates with user confirmation.
metadata:
  author: guido
  version: "1.0.0"
  argument-hint: "[pr-number | branch-name]"
user-invocable: true
---

# Documentation Update Propagator

Analyze the current PR or branch diff, discover documentation artifacts that may be stale, and propose targeted updates. Follow steps exactly.

**Do NOT use the Task tool (subagents). Process everything inline.**

## Step 1: Parse Input

Input mode from skill arguments:
- **Number** → PR mode
- **String** → Branch mode (that branch vs main)
- **No arg** → Branch mode (detect current branch vs main)

Base branch: `main` (fallback: `master`).

### Lock file exclusion

Every `git diff`/`gh pr diff` content command MUST append:
```
-- . ':!pnpm-lock.yaml' ':!package-lock.json' ':!yarn.lock' ':!uv.lock' ':!poetry.lock' ':!Cargo.lock' ':!go.sum' ':!composer.lock'
```

### PR mode

Run **in parallel**:
1. `gh pr view <number> --json title,body,headRefName,baseRefName,additions,deletions,files`
2. `gh pr diff <number>` (with lock exclusion)

If `gh` fails → fall back to branch mode.

### Branch mode

Run **in parallel**:
1. `git branch --show-current` (only if no branch arg)
2. `git log --oneline main..<branch>`
3. `git diff main...<branch> --numstat` (with lock exclusion)
4. `git diff main...<branch>` (with lock exclusion)

## Step 2: Discover & Classify Documentation Artifacts

Scan the repo for all documentation files using Glob:
- `**/*.md`
- `**/*.mdx`
- `**/*.rst`

Exclude: `node_modules/`, `.git/`, `dist/`, `build/`, `.next/`, `.claude/`, `.context/`, `.reviews/`.

Classify each file into a **doc type** and **update policy** using these convention-based rules (first match wins):

| Pattern | Doc Type | Update Policy |
|---|---|---|
| `**/CLAUDE.md`, `**/AGENTS.md` | `agent-instructions` | **Conservative** |
| `**/README.md` at repo root | `root-readme` | **Structural** |
| `**/README.md` inside any subdirectory | `package-readme` | **Structural** |
| `**/*.mdx` | `component-docs` | **Flag-only** |
| Files in dirs named `docs/`, `documentation/`, `doc/` | `guide-or-reference` | **Conservative** |
| Filename matches `*architecture*`, `*design*`, `*adr*`, `*decision*` | `architecture` | **Flag-only** |
| Filename matches `*migration*`, `*changelog*`, `*upgrade*`, `*breaking*` | `migration` | **Flag-only** |
| `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | `community` | **Flag-only** |
| All other `*.md` / `*.rst` | `general-doc` | **Conservative** |

### Policy definitions

- **Structural**: Can propose inline diffs to mechanical sections (tables, lists, command references, structure overviews). Never touches prose paragraphs.
- **Conservative**: Suggests additions or flags stale sections with a description of what to check. Never rewrites existing content.
- **Flag-only**: Lists the file as "check this" with the reason. No proposed edits.

## Step 3: Map Diff to Affected Artifacts

Use three complementary strategies. A doc file is "affected" if ANY strategy flags it.

### A. Proximity mapping (path-based)

For each changed code file in the diff:
1. **Same directory**: flag any doc file (`.md`/`.mdx`) in the same directory or its parent
2. **Sibling docs dir**: if `src/foo/bar.ts` changed, check for `docs/foo/`, `docs/bar.md`, `docs/foo.md`
3. **Package/app README**: if any file under a package or app directory changed, flag that directory's `README.md`
4. **Root docs**: if root-level config files changed (e.g., `package.json`, `turbo.json`, `tsconfig.json`, `Dockerfile`, `.github/workflows/*`, workspace config), flag root `README.md` and any root-level `CLAUDE.md` or `AGENTS.md`

### B. Content mapping (identifier grep)

From the diff, extract key identifiers:
- **Function/method names**: newly exported, removed, or renamed functions
- **Component names**: new or renamed React/Vue/etc. components
- **CLI commands/scripts**: new or changed scripts in `package.json`
- **Class names**: new or renamed classes
- **Config keys**: new or changed configuration options

Then Grep all discovered doc files for these identifiers. Any doc that references a changed/removed identifier is flagged with HIGH confidence. Any doc that references a renamed identifier's OLD name is flagged as **stale reference**.

### C. Structural change detection

- **New directory/workspace added or removed** (detectable from diff numstat showing new top-level dirs) → flag root README and CLAUDE.md
- **Dependency added/removed in any `package.json`** → flag that package's README
- **CI workflow changes** (`.github/workflows/`, `.gitlab-ci.yml`, etc.) → grep docs for CI/deployment mentions, flag those
- **Database schema/migration changes** (Prisma, Drizzle, SQL, Alembic, etc.) → grep docs for database/schema mentions, flag those
- **Docker/infra changes** (`Dockerfile`, `docker-compose.yml`, Helm, k8s) → grep docs for deployment/Docker mentions, flag those

### Deduplication

A doc file may be flagged by multiple strategies. Merge into a single entry, keep the highest confidence, and list all reasons.

### Confidence assignment

- **HIGH**: Content mapping found a stale reference (doc mentions a removed/renamed identifier), OR structural change directly affects a section the doc covers (e.g., new script + doc has a Commands table)
- **MEDIUM**: Proximity mapping flagged the doc AND the diff is substantive (not just formatting)
- **LOW**: Proximity-only flag with no content match, OR the change is minor

## Step 4: Read Affected Docs + Relevant Diff Hunks

For each affected artifact (up to 15 — if more, see Step 4b):
1. Read the full doc file
2. Read the diff hunks for the code files that triggered this mapping
3. Identify what's stale, missing, or needs updating

### Step 4b: Overflow handling

If more than 15 docs are affected:
1. Sort by confidence (HIGH first)
2. Process top 10 in detail
3. List remaining as "also potentially affected" with one-line reasons
4. Ask user: "Process the remaining N docs too, or skip?"

## Step 5: Generate Proposals

For each affected doc, generate a proposal based on its update policy.

### Structural docs (README tables, lists, structure sections)

Produce a concrete diff:
```
File: path/to/README.md
Confidence: HIGH
Reason: New `validateToken()` function exported from auth module, not listed in API table
Policy: Structural

Proposed edit:
  [show the exact old_string → new_string replacement]
```

### Conservative docs (guides, CLAUDE.md, general docs)

Produce a suggestion:
```
File: path/to/CLAUDE.md
Confidence: MEDIUM
Reason: New `test:e2e` script added to root package.json
Policy: Conservative

Suggestion: Consider adding `pnpm test:e2e` to the Commands section (line ~15).
```

### Flag-only docs (MDX, architecture, migration, community)

Produce a flag:
```
File: path/to/component.mdx
Confidence: LOW
Reason: Button component props changed (added `variant` prop)
Policy: Flag-only

Action: Review this file manually — props may need updating.
```

### Stale reference alerts

When content mapping finds a doc referencing a removed or renamed identifier, always produce a HIGH-confidence proposal regardless of policy:
```
File: docs/guide.md
Confidence: HIGH
Reason: References `oldFunctionName` (line 42) which was renamed to `newFunctionName`
Policy: Conservative (override: stale reference)

Suggestion: Replace `oldFunctionName` with `newFunctionName` on line 42.
```

## Step 6: Present Proposals (Batch Mode)

Display all proposals to the user, grouped by confidence:

### HIGH confidence
Show each proposal with full detail (diff or suggestion).

### MEDIUM confidence
Show each proposal with full detail.

### LOW confidence
Show as a compact list (file + one-line reason).

After presenting ALL proposals, ask the user via AskUserQuestion:
- **Accept all** — apply every proposal
- **Review one by one** — go through each, accept/skip individually
- **Skip all** — done, no changes

If "Review one by one": for each proposal, ask:
- **Accept** — mark for apply
- **Skip** — exclude
- **Stop** — done reviewing, apply what's been accepted so far

## Step 7: Apply Accepted Changes

For each accepted proposal:
1. **Structural proposals with concrete diffs**: Apply using the Edit tool
2. **Conservative suggestions**: Apply using the Edit tool (append or insert the suggested content)
3. **Flag-only**: Skip (these are informational only)

After applying all changes, show a summary:
```
Applied N changes to M files:
- path/to/README.md — added row to API table
- path/to/CLAUDE.md — added new script to Commands section
- ...

Skipped K flag-only items (review manually):
- path/to/component.mdx — props may need updating
- ...
```

## Step 8: Catch-All

If the diff touched 5+ code files, list doc files that were NOT flagged by any mapping strategy:

> "These docs weren't flagged automatically. Worth a glance if any are related to your changes:"
> - `path/to/other-doc.md`
> - `path/to/another.md`
> - (max 10 items, skip if none)

## Step 9: Optional Commit Message Draft

If changes were applied, ask the user via AskUserQuestion:
- "Want me to draft a commit message for the doc updates?"
- Options: **Yes** / **No**

If yes, draft a conventional commit message based on the changes made. Present it for the user to review and edit. **Never commit automatically** — always let the user run the commit themselves.

## Rules

- **Never auto-write without user confirmation** — always propose first, apply only after explicit accept
- **Never rewrite curated prose** — flag it, suggest additions, but don't rewrite paragraphs
- **Never create new doc files** — only update existing ones
- **Never touch non-doc files** — this skill only modifies `.md`, `.mdx`, `.rst` files
- **Never touch files in `.git/`, `node_modules/`, `dist/`, `build/`**
- **MDX files are flag-only** — never propose edits to `.mdx` files, only flag them
- **Cap at 15 detailed proposals** — overflow gets a compact list with option to expand
- **Cite your sources** — every proposal must reference the specific code change that triggered it
