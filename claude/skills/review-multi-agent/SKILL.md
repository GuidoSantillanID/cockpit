---
name: review-multi-agent
description: Multi-agent PR review with judge consolidation. Dispatches 3 parallel reviewers with distinct lenses (standards, process, regression), runs a judge to dedupe and verify findings, optionally runs a second verification round. Use when the user asks for a thorough, multi-agent, or consensus-based PR review, or references pro-tips/multi-agent-pr-review.md.
metadata:
  author: guido
  version: "1.0.0"
  argument-hint: "[scope-glob]"
user-invocable: true
---

# Multi-Agent PR Review

Invocation wrapper for the playbook at `pro-tips/multi-agent-pr-review.md`
(cockpit repo). The playbook is the source of truth for agent roles, severity
definitions, finding schema, envelope schema, and judge process. **Load it
before dispatching anything** — this skill is only the entry point, pre-flight
checklist, and output rendering.

## Step 0: Locate and read the playbook

Try in order:
1. `<cwd>/pro-tips/multi-agent-pr-review.md`
2. `/Users/guido/Documents/dev/cockpit/pro-tips/multi-agent-pr-review.md`
3. Ask the user for the path.

Read the full playbook before Step 1. Do not skim.

## Step 1: Pre-flight checklist (MANDATORY)

Fill in every field before dispatching. Do NOT dispatch until all fields are
resolved and emitted to the user as a visible block — guessing wastes agent
budgets and hides assumptions.

| Field | Resolution |
|---|---|
| `base` | Default `origin/main`. Confirm with `git remote -v` if unsure. |
| `head` | Default `HEAD`. |
| `path_filter` | From skill argument if provided, else ask the user or default to `**`. |
| `files_changed` | `git diff --name-only <base>...<head> -- <path_filter>` piped to `wc -l`. |
| `rounds` | Default `R1`. Add `R2` if diff touches auth/sec, dep upgrades, production-critical paths, or exceeds ~100 files. |
| `agents` | Default roster: Agent 1 (standards), Agent 2 (process), Agent 4 (regression). Agent 3 (structured) is optional. Skip any agent whose lens has no surface in the diff — record in `envelope.skipped_agents` with a reason. |
| `chunks` | If `files_changed > 50`, split by directory or feature slice per playbook §Run envelope. Target ≤ 50 files per agent. Do NOT chunk by reviewer lens alone. |
| `budget_cap_usd` | Default 1.50 per round. |

Emit the checklist in a markdown block and pause for user override before
dispatch. Treat no response within a reasonable window as implicit approval
of the defaults.

## Step 2: Round 1 dispatch

Dispatch the resolved agent roster **in parallel within a single 5-min window**
(warm cache). Agent-type mapping per playbook:

- **Agent 1 (standards)** → `superpowers:code-reviewer`, receives intent context (branch name, commit subjects, ticket).
- **Agent 2 (process)** → `superpowers:requesting-code-review` skill, bash-capable, receives intent context.
- **Agent 4 (regression)** → general-purpose, **metadata-blind** (no branch name, no commit subjects, no ticket — confirmation-bias defense per playbook).
- **Agent 3 (structured, optional)** → `/review-pr` skill, receives intent.

Every finding MUST include `verification_command`. See playbook §Finding schema.

**If any agent stalls** (600s no-progress watchdog, ~10-min stream idle):
re-dispatch that agent with a narrower scope — do NOT accept partial output.
Same for agents that were paused mid-run and re-resumed with a stale stream.

## Step 3: Judge

Sonnet, temperature 0.25, metadata-stripped input (no branch/commit/ticket).
Follow playbook §Judge Phase steps 1–7:

1. Verification pass — run every `verification_command`; drop on failure.
2. HubSpot 3-criteria filter (succinct / accurate / actionable).
3. Category caps per playbook.
4. High-confidence promotion (≥ 2 reviewers flag the same file/line).
5. Severity assignment.
6. Emit JSON envelope (with `scope`, `rounds_run`, `skipped_agents`).
7. Render markdown summary alongside the envelope.

## Step 4: Report to the user

Present in this order:

1. **Markdown summary** first — grouped by severity descending, one line per finding: `` `file:line` — one-sentence message (tags) ``. Tags include `high_confidence` and `source_reviewer` values.
2. **JSON envelope** second, in a fenced code block for Fix Phase agents and future automation.
3. **Next-step suggestion**:
   - Fix Phase if any BLOCKING or SHOULD-FIX findings.
   - Round 2 if stakes warrant and it hasn't run.
   - Stop if clean.

If verdict is clean: one confirming sentence, then stop. Silence is a feature.

## Step 5 (optional): Round 2

Run only when the pre-flight set `rounds: R1+R2` or a BLOCKING was found in R1.
Follow playbook §Round 2 exactly: fresh context, NO R1 findings passed in, all
5 agents metadata-blind. Re-run the judge over the union of R1 + R2 findings.

## What NOT to do

- Do NOT run Round 2 by default. Most PRs stop at R1 + judge.
- Do NOT dispatch before emitting the pre-flight checklist.
- Do NOT skip the markdown rendering — raw JSON alone is noise for the user.
- Do NOT trust findings without `verification_command` — the judge runs them.
- Do NOT chunk by reviewer lens alone when files_changed > 50 — chunk by directory.
- Do NOT accept partial output from a stalled or paused-then-resumed agent — re-dispatch with narrower scope.
- Do NOT strip metadata from the standards/process agents — they need intent. Strip ONLY from regression (Agent 4) and the judge.
