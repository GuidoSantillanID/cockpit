---
name: review-pr
description: Generates a structured PR review guide. Analyzes diff, categorizes files by review priority, detects AI code red flags, and writes a .md review guide.
metadata:
  author: guido
  version: "4.1.0"
  argument-hint: "[pr-number | branch-name]"
user-invocable: true
---

# PR Review Guide Generator

Generate a structured review guide for a PR or local branch. Follow steps exactly.

**Do NOT use the Task tool (subagents). Process everything inline.**

## Step 1: Parse & Fetch

Input mode from skill arguments:
- **Number** → PR mode
- **String** → Branch mode (that branch)
- **No arg** → Branch mode (detect current branch)

### Lock file exclusion

Every `git diff`/`gh pr diff` content command MUST append:
```
-- . ':!pnpm-lock.yaml' ':!package-lock.json' ':!yarn.lock' ':!uv.lock' ':!poetry.lock' ':!Cargo.lock' ':!go.sum' ':!composer.lock'
```
Lock files appear in `--numstat`/`--stat` for counts but content is never read.

### PR mode

Run **in parallel**:
1. `gh pr view <number> --json title,body,author,headRefName,baseRefName,url,additions,deletions,state,files`
2. `gh pr diff <number> -- . ':!pnpm-lock.yaml' ...` (with full lock exclusion)
3. Read `CONTRIBUTING.md` and `AGENTS.md` (skip silently if missing)

If `gh` fails → fall back to branch mode. If `gh` not installed → tell user to install/auth.

### Branch mode

Run **all in parallel**:
1. `git branch --show-current` (only if no branch arg)
2. `git log --oneline main..<branch>`
3. `git diff main...<branch> --numstat`
4. `git diff main...<branch> --stat`
5. Read `CONTRIBUTING.md` and `AGENTS.md` (skip silently if missing)

Base branch: `main`. Do NOT fetch full diff yet.

### Diff strategy

After `--numstat`, count changed files (excluding lock files):
- **<30 files**: Fetch full diff in one command with lock exclusion.
- **30+ files**: Use `--numstat`/`--stat` + path heuristics to assign tiers first. Then fetch full diffs **only for CRITICAL and HIGH** via per-file commands in parallel. MEDIUM/SKIP get guidance from file name + stat only.

## Step 2: Jira Ticket (best-effort)

Check branch name for `[A-Z][A-Z0-9]+-\d+`. No match → skip entirely (no MCP calls).

If match: use `mcp__claude_ai_Atlassian__getJiraIssue` (load via ToolSearch first). On any failure → skip silently.

## Step 3: Categorize & Skip

Single pass: classify every file into a tier. Highest matching tier wins (path-based, not size-based).

### Skip detection

Auto-SKIP: lock files, generated code (`generated`, `__generated__`, `*.g.cs`, `*.pb.*`), build artifacts (`dist/`, `build/`, `.next/`), IDE noise, sourcemaps, binary files, formatting-only changes.

**Formatting-only detection** (three methods, try in order):
1. **Diff inspection** (when diff is available): every removed line has a corresponding added line identical after stripping whitespace/semicolons/quotes/trailing-commas/import-order → SKIP.
2. **Commit-message signal** (for large PRs where MEDIUM/SKIP diffs aren't fetched): a commit message explicitly describes formatting (`style:`, `chore: format`, `fix lint`, `reorder imports/classes`) AND the file's numstat shows balanced +/- → SKIP. Tag: `(inferred from commit <hash>)`.
3. **Stat-only heuristic** (when commit messages are uninformative): if a MEDIUM-tier file has roughly balanced +/- (within 20%), net change ≤3 lines, AND 10+ sibling files in the same directory show the same pattern → SKIP the group. Tag: `(inferred from stat pattern)`. This catches bulk reformatting even with bad commit messages, but is conservative — a single file with balanced stats is NOT enough.

**Promotion rule**: if any substantive change is found later (during review or diff spot-check), promote to appropriate tier.

### CRITICAL — line-by-line review
API contracts, auth/security, DB migrations/schemas, infra/deploy (Dockerfile, CI workflows, Helm, k8s), dependency manifests (NOT lock files).

### HIGH — review with intent
Business/domain logic, endpoints/routes, state management, error handling, data access.

### MEDIUM — spot-check
Tests, UI components, styling, docs, non-critical config.

When 10+ MEDIUM files share same parent dir and change pattern → group into one entry.

## Step 4: Analysis

### Per-file guidance (CRITICAL & HIGH only)
Read diff carefully. Write 1-2 sentences of specific review guidance covering: correctness, naming, boundaries, error paths, testability, simplicity.

For MEDIUM files: group by category with count. No per-file guidance.

### Cross-component warnings (structural only)
- Files spanning 2+ top-level dirs → contract consistency
- Client + server touched → API contract sync
- Migrations + app code → deployment ordering
- Check `AGENTS.md`/`CONTRIBUTING.md` anti-patterns if available

### AI red flags
Patterns: over-engineering, hallucinated imports, shallow tests, copy-paste artifacts, security blind spots, convention ignorance, missing error handling, unnecessary changes.

Record: file path, one sentence, severity (`WARNING`/`INFO`).

## Step 5: Output Mode

Before writing, ask the user using the AskUserQuestion tool:
- Question: "How should I output the review guide?"
- Options:
  1. **Save to file** — Write to `.reviews/` directory (default)
  2. **Print here** — Output the full review guide inline in chat

If user picks **Save to file** → create `.reviews/` directory if needed and write the file as described below.
If user picks **Print here** → output the full markdown review guide directly in the chat response. Do NOT create any files.

## Step 6: Write Output

**Deduplication rules**:

1. **File uniqueness**: Every file appears in exactly ONE tier. If a file's guidance was written in CRITICAL, it MUST NOT also appear in HIGH or MEDIUM. No file path should appear in two tier lists.
2. **Section jobs**: Each section has ONE job. Never restate the same issue across sections:
   - **Key Findings**: top 3-5 risks ("start here"). Brief, no file-level detail.
   - **File Review Guide**: per-file guidance. If an issue is already in Key Findings, write "See Key Findings" — don't restate.
   - **Cross-Component Warnings**: structural/architectural concerns ONLY (not file-level issues already in File Review Guide).
   - **AI Red Flags**: AI-specific patterns ONLY (not general issues already covered above).

When saving to file, create `.reviews/` directory if needed. Output:
- PR mode: `.reviews/pr-<number>.md`
- Branch mode: `.reviews/pr-<branch-name>.md` (replace `/` with `-`)

### Template — use this exact format

```markdown
# PR Review Guide: #<number>
> Generated on <YYYY-MM-DD>

## Key Findings
- **Risk**: <LOW/MEDIUM/HIGH — one sentence>
- <most important thing to verify>
- <second most important>
- <3-5 bullets total>

## Summary
| Field | Value |
|---|---|
| Title | ... |
| Author | ... |
| Branch | `head` -> `base` |
| Size | +X / -Y |
| Files | N changed (M to review, K skippable) |

## Jira Ticket
| Key | Summary | Type | Status | Priority |
|---|---|---|---|---|
| ... | ... | ... | ... | ... |

> Description excerpt (first ~500 chars)

## PR Description
> Body excerpt (max 1000 chars)

## Components Touched
- `dir/` — N files

## File Review Guide

### CRITICAL
1. **`file.ts`** — What to verify; specific guidance
2. **`other.yml`** — What to verify; specific guidance

### HIGH
1. **`service.ts`** — What to verify; specific guidance

### MEDIUM — N files
- **ESLint configs** — 4 new `eslint.config.mjs` files (flat config migration)
- **TypeScript configs** — 3 files (module resolution, target changes)
- **Docs** — 5 files (README, CONTRIBUTING, ADRs)
- `seed.ts` — seed data changes
- `loading.tsx` — new loading boundary

### SKIP — N files
<details>
<summary>Skipped files</summary>

- `packages/ui/components/` — 45 files (Tailwind class reorder only)
- `apps/web/features/` — 8 files (formatting)
- 4 deleted `.eslintrc.js` files (replaced by flat config)
- `pnpm-lock.yaml`
</details>

## Cross-Component Warnings
- [WARN] description...

## AI Red Flags
- [WARNING] `file` — description
- [INFO] `file` — description

## Reviewer Checklist
- [ ] Understand the intent (PR description + Jira ticket)
- [ ] Review all CRITICAL files line-by-line
- [ ] Confirm no secrets/credentials in diff
```

### Format rules
- CRITICAL and HIGH: **numbered list** with bold file name + guidance. No tables.
- MEDIUM: **grouped list** like SKIP. Group by category (e.g., "ESLint configs — 4 files", "Docs — 5 files"). Individual files only when they don't fit a group. No flat file-per-row tables.
- SKIP: **grouped by reason** (dir + count + reason). Never list 10+ files individually — group by parent dir or change pattern. When using commit-message inference for formatting-only, include `(inferred from commit <short-hash>)`.
- Conditional sections (Jira, PR Description, Cross-Component Warnings, AI Red Flags): omit entirely if no content. No headers, no placeholders.

### Dynamic checklist
Only include items relevant to THIS PR. Select from:

| Condition | Checklist item |
|---|---|
| Always | Understand the intent (PR description + Jira ticket) |
| Always | Review all CRITICAL files line-by-line |
| Always | Confirm no secrets/credentials in diff |
| Has migrations | Verify migration rollback safety |
| Has Docker/infra | Run `docker build` locally |
| Has CI changes | Verify CI pipeline on a test branch |
| Has new endpoints | Verify auth/authz on new endpoints |
| Has new deps | Check new dependency licenses and maintenance status |
| Has tests | Verify tests cover behavior, not implementation |
| Has API changes | Check for breaking changes in public APIs |

### Branch mode adjustments
- Title: `# Branch Review Guide: <branch>`
- Summary: omit URL, add `| Commits | N |`
- Omit PR Description section

### Large PR handling
- **50+ files**: Add warning at top to focus on CRITICAL + HIGH first.
- **100+ files**: MEDIUM becomes file names only (already the default format).

## Step 7: Report to User

Print brief summary:
- File path of review guide (if saved to file) or note it was printed inline
- Files per tier (CRITICAL / HIGH / MEDIUM / SKIP)
- AI red flags count
- Suggest starting with CRITICAL files
- Branch mode: note no PR exists yet, suggest creating one
- If any MEDIUM+ tier files are documentation (`.md`, `.mdx`, `.rst`), add: "Docs were changed or may be stale — run `/update-docs` to check for propagation."
