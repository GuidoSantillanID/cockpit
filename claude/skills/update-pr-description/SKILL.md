---
name: update-pr-description
description: Updates the current PR's title and description on GitHub. Detects repo PR template, then generates and applies title + description via gh pr edit.
metadata:
  author: guido
  version: "2.0.0"
  argument-hint: "[pr-number]"
user-invocable: true
---

# PR Title & Description Updater

Generate and apply an updated title and description for the current branch's PR based on diff and commits. Follow steps exactly.

**Do NOT use the Task tool (subagents). Process everything inline.**

## Step 1: Resolve PR

Input mode from skill arguments:
- **Number** → use that PR number directly
- **No arg** → detect current branch and find its open PR

### No-arg mode

Run in parallel:
1. `git branch --show-current`
2. Check if `gh` is installed: `gh --version`

If `gh` not installed → "gh CLI not found. Install from https://cli.github.com/" and stop.

If on `main` or `master` with no arg → "You're on the base branch. Switch to a feature branch or pass a PR number." and stop.

Then: `gh pr view --json number,title,body,headRefName,baseRefName,url,state`

If command fails (not authenticated) → "gh is not authenticated. Run: gh auth login" and stop.
If no open PR for branch → "No open PR found for branch `<name>`. Create one first with `gh pr create`." and stop.
If PR state is `MERGED` or `CLOSED` → "PR #N is <state>. Only open PRs can be updated." and stop.

Store: `pr_number`, `current_title`, `current_body`, `head_branch`, `base_branch`, `pr_url`.

### Number-arg mode

`gh pr view <number> --json number,title,body,headRefName,baseRefName,url,state`

Apply same error handling and state checks above.

## Step 2: Gather Diff + Commits

Lock file exclusion (append to all diff commands):
```
-- . ':!pnpm-lock.yaml' ':!package-lock.json' ':!yarn.lock' ':!uv.lock' ':!poetry.lock' ':!Cargo.lock' ':!go.sum' ':!composer.lock'
```

Run **in parallel**:
1. `gh pr diff <pr_number>` (with lock file exclusion)
2. `gh pr view <pr_number> --json commits`
3. `git log --oneline <base_branch>..<head_branch>`

If diff is empty → "PR #N has no changes vs `<base>`. Nothing to generate." and stop.

## Step 3: Detect Template

### 3a. PR Template File

Glob for (run all in parallel):
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/pull_request_template.md`
- `.github/PULL_REQUEST_TEMPLATE/default.md`
- `docs/pull_request_template.md`

If any found: read it. This is the `description_template`. Set `template_source = "pr_template"`. → Go to Step 4.

### 3b. Fallback

`template_source = "conventional_commits"`. No `description_template` — use the standard format in Step 5.

## Step 4: Generate Title

**4a. Extract ticket ID**
Regex on `head_branch`: `([A-Z][A-Z0-9]+-\d+)`. Store as `ticket_id` (or null if not found).

**4b. Determine commit type**
From commit messages, extract conventional commit prefixes (`feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `ci`, `build`, `perf`, `style`). Take the majority. If none found, infer from branch prefix:
- `feature/`, `feat/` → `feat`
- `fix/`, `bugfix/`, `hotfix/` → `fix`
- `chore/` → `chore`
- `refactor/` → `refactor`
- `docs/` → `docs`
- `test/` → `test`
- Otherwise → `feat`

**4c. Synthesize summary phrase**
From commit messages: strip prefixes, strip ticket references, deduplicate similar messages. Condense to a single lowercase phrase (5–10 words) that captures the overall intent.

**4d. Assemble title**
- With ticket: `[TICKET-ID] type: summary`
- Without ticket: `type: summary`

## Step 5: Generate Description

### If `description_template` exists (from 3a):

Fill each section using best judgment from the diff and commits. Leave all checklists unchecked — those are the user's responsibility.

### If no template (fallback):

Generate this structure exactly:

```markdown
## Summary
<1–3 sentences synthesizing the overall change from commits and diff — what and why>

## Changes
- <bullet: area or component — what changed, inferred from diff + commits>
- <bullet: ...>
- (3–7 bullets total; group by logical area, not by file)

## Ticket
<ticket ID>
```

Omit the `## Ticket` section entirely if no ticket ID was detected.

## Step 6: Propose + Confirm

Present the proposal in this format:

```
### Current
**Title:** <current_title>
**Description:**
<current_body — truncated to first 500 chars if longer, with "(… truncated)" note>

---

### Proposed
**Title:** <generated title>
**Description:**
<generated description>

---
Convention: <template_source>
```

Then use `AskUserQuestion`:
- Question: "Apply this title and description to PR #<pr_number>?"
- Options:
  1. **Apply** — Update the PR on GitHub now
  2. **Cancel** — Keep the current title and description

### If Apply:

Run:
```bash
gh pr edit <pr_number> --title "<generated title>" --body "$(cat <<'PREOF'
<generated description>
PREOF
)"
```

If successful, print:
```
Updated PR #<pr_number>: <pr_url>
Title: <generated title>
Convention: <template_source>
```

If `gh pr edit` fails, print the error verbatim and stop.

### If Cancel:

Print: "No changes made."

## Error Reference

| Condition | Behaviour |
|---|---|
| `gh` not installed | Print install URL, stop |
| `gh` not authenticated | Print `gh auth login`, stop |
| On main/master, no arg | Explain, stop |
| No open PR for branch | Suggest `gh pr create`, stop |
| PR merged or closed | State the PR state, stop |
| Empty diff | Explain, stop |
| PR template not found | Fall through to conventional commits |
