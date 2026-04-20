---
name: review-multi-agent
description: Multi-agent PR review with judge consolidation. Auto-detects R1 (fresh branch) vs R2 (post-fix branch). Dispatches 3 parallel reviewers (aligned + adversarial + tests on R1; aligned + adversarial + fix_verifier on R2), runs a judge to verify, dedupe, and rank findings. Use when the user asks for a thorough, multi-agent, or consensus-based PR review, or references pro-tips/multi-agent-pr-review.md.
metadata:
  author: guido
  version: "2.0.0"
  argument-hint: "[scope-glob]"
user-invocable: true
---

# Multi-Agent PR Review

Invocation wrapper for the playbook at `pro-tips/multi-agent-pr-review.md`
(cockpit repo). The playbook is the source of truth for agent roles,
severity definitions, finding schema, envelope schema, and judge process.
**Load it before dispatching anything** — this skill is only the entry
point, pre-flight, pass-detection, and output rendering.

One skill invocation = one audit pass (R1 or R2). If the user runs Fix
Phase between passes, re-invoke the skill to get the R2 audit.

## Step 0: Locate and read the playbook

Try in order:
1. `<cwd>/pro-tips/multi-agent-pr-review.md`
2. `/Users/guido/Documents/dev/cockpit/pro-tips/multi-agent-pr-review.md`
3. Ask the user for the path.

Read the full playbook before Step 1. Do not skim.

## Step 1: Pre-flight checklist (MANDATORY)

### 1a. Multi-component scope check (do this FIRST)

If the diff spans **2+ top-level components/packages**, ask the user
which scope to review **before** building the checklist. Do NOT pre-chunk
everything and wait for them to narrow.

Detect with:

```bash
git diff --name-only <base>...<head> | awk -F/ 'NF>=2 { print $1"/"$2 }' | sort -u
```

If 2+ distinct prefixes return, list them with file counts and ask a
single question: "Which scope? (e.g., `components/web/**`, or `all`)".
Use the answer as `path_filter` below.

### 1b. Detect pass type (R1 vs R2)

Check for a prior review-fix commit on the branch:

```bash
git log --grep="address.*review.*findings" --grep="multi-agent.*review" -i --oneline <base>...<head>
```

- **No match → R1 pass** (fresh audit). Agent roster: aligned +
  adversarial + tests.
- **Match found → R2 pass** (audit the fixes). Agent roster: aligned +
  adversarial + fix_verifier. The fix_verifier needs the R1 findings —
  if not available, ask the user for the R1 envelope (JSON) or the
  markdown summary. Without it, fix_verifier degrades to a second
  adversarial agent.

### 1c. Resolve the checklist

Fill every field before dispatching. Emit the checklist as a visible
markdown block and pause for user override.

| Field | Resolution |
|---|---|
| `base` | Default `origin/main`. Confirm with `git remote -v` if unsure. |
| `head` | Default `HEAD`. |
| `path_filter` | From Step 1a answer, or skill argument, else ask. Default `**` only if no multi-component split exists. |
| `files_changed` | `git diff --name-only <base>...<head> -- <path_filter>` piped to `wc -l`. |
| `pass` | From Step 1b: `R1` or `R2`. |
| `agents` | R1: aligned + adversarial + tests. R2: aligned + adversarial + fix_verifier. Skip any whose lens has no surface in the diff — record in `envelope.skipped_agents` with reason. |
| `chunks` | **Default: no chunking** (one chunk per lens covering the full `path_filter`). Chunk only when `files_changed > 200` per agent, a prior run stalled on this diff, or the user explicitly requests it. See playbook §Run envelope → Chunking. Do NOT chunk by reviewer lens alone. |
| `budget_cap_usd` | Default 1.50 per phase. |
| `skip_r2` | Only set if user explicitly opted out of R2 in pre-flight (low-stakes PR). Ignored on R1 passes. |

Treat no response within a reasonable window as implicit approval of
the defaults.

## Step 2: Dispatch

Fire all 3 agents **in parallel within a single 5-min window** (warm
cache). Agent-type mapping per playbook §R1 and §R2:

**R1 pass:**
- **aligned** → `superpowers:code-reviewer`. Receives intent context
  (branch name, commit subjects, ticket).
- **adversarial** → general-purpose. **Metadata-blind** — no branch
  name, no commits, no ticket.
- **tests** → bash-capable general-purpose. Narrow scope: detect and
  run the project test command (180s cap). Emit failures as findings.

**R2 pass:**
- **aligned** → `superpowers:code-reviewer`. Receives branch name +
  AGENTS.md + `docs/patterns/*`. **Commit subjects withheld** — on
  post-fix branches they leak "bugs already fixed" framing (see
  playbook §R2 agents).
- **adversarial** → general-purpose. Metadata-blind. Same charter; look
  for fix-induced regressions and R1 recall gaps.
- **fix_verifier** → general-purpose. Receives the R1 findings list +
  post-fix diff (explicit exception to R2's clean-context rule).
  For each R1 finding, confirms: fix was applied, addresses root
  cause, introduced no new issues in the fix's scope.

Every finding MUST include `verification_command` — the judge drops
findings missing it.

**If any agent stalls** (600s no-progress watchdog, ~10-min stream
idle): re-dispatch that agent with a narrower scope. Do NOT accept
partial output from a stalled or paused-then-resumed agent.

## Step 3: Judge

Sonnet, temperature 0.25, metadata-stripped input (no branch/commit/ticket).

**Handoff format: inline.** Embed findings directly in the judge prompt
body as JSON (or NDJSON for >200 findings). **Never** write findings
to a `/tmp/*.json` file and pass the path — see playbook §Judge →
Input for the failure mode that rule exists to prevent.

Follow playbook §Judge steps 1–6:

1. Verification pass — run every `verification_command`; drop on failure.
2. HubSpot 3-criteria filter (succinct / accurate / actionable).
3. Category caps per playbook.
4. High-confidence promotion (≥2 reviewers flag the same file/line).
5. Severity assignment.
6. Emit JSON envelope (with `scope`, `pass`, `budget_spent_usd`)
   + markdown summary. `pass` is a single string: `"R1"` or `"R2"`
   (one envelope per skill invocation; the cumulative R1+Fix+R2
   pipeline is tracked across invocations in the runs log, not in one
   envelope).

## Step 4: Report

Present in this order:

1. **Markdown summary first** — grouped by severity descending, one
   line per finding: `` `file:line` — one-sentence message (tags) ``.
   Tags: `HC` for `high_confidence`, plus `source_reviewer` values.
2. **JSON envelope second**, in a fenced code block for Fix Phase
   agents and future automation.
3. **Next-step suggestion:**
   - **R1 pass with findings:** recommend Fix Phase (parallel clusters,
     TDD, per playbook §Fix Phase), then re-invoke this skill for R2.
   - **R2 pass with findings:** recommend another Fix Phase cycle.
   - **Clean verdict (either pass):** one confirming sentence, stop.
     Silence is a feature.

## What NOT to do

- Do NOT dispatch before emitting the pre-flight checklist.
- Do NOT skip the pass-type detection (Step 1b) — wrong roster wastes
  a run.
- Do NOT strip metadata from the R1 aligned, tests, or fix_verifier
  agents — they need intent. R2 aligned gets branch name + AGENTS.md
  but NOT commit subjects (bias hygiene). Adversarial and the judge
  are fully metadata-stripped in both passes.
- Do NOT trust findings without `verification_command` — the judge
  runs them.
- Do NOT chunk by reviewer lens alone. Chunk by directory/feature if
  `files_changed > 200` per agent.
- Do NOT accept partial output from a stalled or paused-then-resumed
  agent — re-dispatch with narrower scope.
- Do NOT skip the markdown rendering — raw JSON alone is noise.
- Do NOT run Fix Phase from inside this skill. Fix Phase is a separate
  orchestration (parallel dev clusters with write access); this skill
  is audit-only (`permissionMode: plan`).
