# Multi-Agent PR Review with Judge Consolidation

> Playbook for reviewing a PR with parallel subagents + a judge.
> Evidence log: `multi-agent-pr-review.runs.md` (append-only, one entry
> per real run). Research backing: `multi-agent-code-review-reference.md`.
> Iteration guidance at bottom.

Run parallel reviewers with distinct lenses, consolidate via a judge
that verifies every finding, apply fixes in parallel clusters with TDD,
then re-audit the post-fix tree. Overlap between lenses is intentional
(wisdom-of-crowds); dedup happens at the judge.

---

## Default pipeline

```
R1 audit         Judge            Fix phase        R2 audit         Judge
(3 agents, ||)   (verify+rank)    (parallel       (3 agents, ||)    (verify+rank)
                                  clusters, TDD)
     │               │                │                │                │
     ▼               ▼                ▼                ▼                ▼
  findings  →  filtered list  →  fixes applied  →  post-fix audit → verdict
                                                                        │
                                                    if findings, loop fix → R2
                                                    else: ship
```

**R2 runs by default whenever Fix Phase ran.** Skip only with explicit
`--skip-r2` in pre-flight (e.g. low-stakes PR, user owns the risk).

**If R1 judge emits `clean`, stop.** No Fix Phase, no R2.

---

## Run envelope

Target per run (<50-file branch):

- **Cost:** ~$0.30–$0.80 with prompt caching; cap $1.50/phase
- **Wall clock:** R1 ~3–6 min; judge ~30s–2 min; Fix ~5–10 min;
  R2 ~5–15 min; total ~15–40 min
- **Abort:** `cost_usd >= 1.50` OR `wall_clock_sec >= 600` per phase;
  emit partial report on trip
- **Scale caps proportionally** for >50-file diffs. Record
  `budget_spent_usd` per round in the envelope.

**Chunking (default: off).** No chunking up to ~200 files per agent.
Chunk only when: a prior unchunked run stalled (idle timeout), OR >200
files/agent AND diff spans orthogonal slices, OR user requests in
pre-flight. Prefer directory/feature chunks; never chunk by reviewer
lens (orthogonal to file count).

---

## R1 — Initial audit (3 agents, parallel)

Fire all within 5 min to hit the warm prompt cache (shared prefix =
system + AGENTS.md + compressed diff).

### Aligned reviewer (`source_reviewer: aligned`)

Use `superpowers:code-reviewer`. **Receives intent context** (branch
name, commit subjects, ticket, AGENTS.md, `docs/patterns/*`).

- Project conventions, architectural violations, code quality
- Workaround quality — clean or hacky?
- Consistency, naming, AI-red-flag over-engineering

### Adversarial reviewer (`source_reviewer: adversarial`)

General-purpose agent. **Metadata-blind** — NO branch name, NO commit
subjects, NO ticket. Receives compressed diff + AGENTS.md +
installed third-party source.

Confirmation-bias defense: framing a diff as "bug-free" drops
vulnerability detection 16–93% ([arXiv 2603.18740](https://arxiv.org/html/2603.18740));
metadata strip + explicit de-biasing recovers 94%.

- Assume nothing is correct. Hunt for regressions, wrong comments,
  missed migrations, stale workarounds, silent runtime failures,
  fragile workarounds
- Verify third-party claims by **reading the installed file** (not
  grep) — grep misses symlinks, pnpm content-addressed store, compiled
  output, TS path aliases, dynamic imports, reflection
- Lockfile/dep verification when relevant
- Flag over-abstracted or "extremely AI" solutions

### Test runner (`source_reviewer: tests`)

Bash-capable. Narrow scope: **detect and run the project's test command**.

- Priority: `package.json scripts.test` → `pyproject.toml` →
  `Makefile` → `justfile` → direct runners
- Cap at 180s
- Emit each failure as a finding with the exact reproduction command

No static checks (TODO/FIXME/WIP-marker/secret-file hunting). Those
are low-value as reviewer output (Run 2: zero BLOCKING/SHOULD-FIX from
the full Process lens) — fold into a pre-commit hook if you want them.

---

## Judge

Run after all R1 agents complete.

- **Model:** Sonnet 4.6. Opus is overkill on pre-filtered input.
- **Temperature:** 0.25
- **Input:** reviewer findings only, inline in the prompt body (NDJSON
  preferred for >200 findings). **No `/tmp/*.json` round-trips** — a
  dogfood run produced a corrupted intermediate file; inline findings
  fail loudly if malformed and stay in the conversation log.
- **Metadata strip:** judge sees NO branch name, NO commits, NO ticket,
  NO author (same confirmation-bias defense as the Adversarial reviewer).
- **De-biasing line:** judge prompt must include a short statement that
  the diff has not been pre-vetted and every finding's claim must be
  proven by its `verification_command`, not assumed correct. Metadata
  redaction and de-biasing are additive interventions, not either/or
  ([arXiv 2603.18740](https://arxiv.org/html/2603.18740) — the 94%
  detection recovery reported requires both together; denominators
  differ slightly between conditions, so treat the gap as "redaction +
  de-biasing recovers more than redaction alone," not a precise 68/94
  split). Keep the line to one sentence — longer prompts introduce
  verbosity-bias.

### Process

1. **Verify.** Every finding must include `verification_command`. Run
   it. Drop on non-zero exit, empty output, or contradicted claim
   (reason: `verification_failed`). Drop findings missing the field
   (reason: `missing_verification_command`).

   Plan-mode judges without shell: delegate verification to a read-only
   subagent. The rest of the judge flow runs on JSON alone.

2. **Filter** (HubSpot 3-criteria gate — all three must pass):
   - **Succinct** — actionable without re-reading?
   - **Accurate** — grounded in the diff?
   - **Actionable** — concrete fix, not hand-wringing?

3. **Cap low-value categories** (Qodo reflect-prompt pattern):
   - Cap at SHOULD-FIX: generic error-handling / type-checking
     without a concrete failure mode
   - Cap at WATCH: "verify X" without a concrete claim; cosmetic or
     tautological proposed change
   - Drop (`category_cap`): type-hint-only, docstring-only,
     unused-import-only, "use more specific exception types"

4. **High-confidence promotion.** ≥2 reviewers flag the same file/line
   with compatible messages → `high_confidence: true`. Join
   `source_reviewer` with `+`.

5. **Severity assignment** per §Severity.

6. **Output** — JSON envelope (below) + human-readable markdown
   summary. If nothing passes: emit `{"status":"clean"}` and a one-line
   markdown verdict. **Silence is valid output.**

### Envelope

```json
{
  "status": "findings | clean",
  "verdict": "Ready | Needs Attention | Needs Work",
  "summary": "one line",
  "scope": {
    "base": "origin/main",
    "head": "HEAD",
    "path_filter": "components/web/**",
    "files_changed": 148,
    "chunks": [ { "agent": "all", "paths": ["..."], "files": 148 } ]
  },
  "pass": "R1 | R2",
  "budget_spent_usd": { "R1": 0.42, "judge": 0.08, "Fix": 0.15, "R2": 0.31 },
  "findings": [ /* per §Finding schema */ ],
  "dropped": [
    {
      "original": { /* per §Finding schema */ },
      "reason": "verification_failed | missing_verification_command | category_cap | not_succinct | not_accurate | not_actionable"
    }
  ]
}
```

### Markdown summary

Render after the envelope. This is what the human reads; the envelope
is for Fix Phase and programmatic use.

```
**Verdict:** Needs Work — 2 BLOCKING, 5 SHOULD-FIX, 3 WATCH, 1 NIT
**Scope:** components/web/** (148 files) · R1+Fix+R2

### BLOCKING
- `app/api/runs/route.ts:19` — case-insensitive search regression (HC: aligned+adversarial)
- `app/api/upload/route.ts:7` — no null guard on jobId/uploadId (HC: adversarial+tests)

### SHOULD-FIX
- ...

### Dropped (11): 2 verification_failed · 4 category_cap · 5 not_actionable
```

One line per finding. Group by severity descending, omit empty
sections. Tags: `HC` for high-confidence + the source reviewers.
Dropped findings: summarize by reason count, don't list individually.
Keep under ~40 lines.

---

## Fix Phase

Apply fixes in **parallel dev clusters with non-overlapping file scopes.**
Validated pattern from Run 2 (4 clusters, ~4 min wall-clock, all fixes
landed cleanly).

### Cluster design

- Group findings by directory/feature. One dev agent per cluster.
- Clusters MUST have disjoint file scope (no two clusters writing the
  same file).
- Findings that span cluster boundaries: assign to the cluster that
  owns the majority, flag as `cross_cluster: true` for the R2 pass.

### Per dev agent

- Writes fixes, scoped to the findings assigned to this cluster.
- **Red-green TDD for every BLOCKING with a reproducible failure
  mode** (UI crash, API 5xx, assertion failure, lint/typecheck error,
  test failure): failing test first → fix → passing test. Non-negotiable.
  Run 2 evidence: fix-induced regressions that slipped through (lint
  bug, half-done sentinel, dead abstraction) were all non-UI — the
  rule needs to cover any reproducible failure, not just UI.
- Runs per-cluster typecheck + lint + tests before returning.
- **Under-scoping rule:** if a finding flags a pattern in one file,
  grep for all instances in the `path_filter` and fix the full set.
  Under-scoping was the failure mode in 3 Run 2 findings.

### After all clusters complete

- Run the whole-app typecheck + lint + test suite. Per-cluster checks
  miss semantic regressions and cross-cluster interactions (Run 2
  evidence: CI-breaking lint bug, half-done sentinel fix, dead
  abstraction all slipped through per-cluster checks).

### Third-party SDK findings

Before any dev agent applies a fix that depends on a claim about a
third-party package's behavior: launch a research agent to re-verify
by reading the installed code. Do NOT trust the original reviewer's
claim alone. Run 1 nearly shipped a "dead code" fix that was wrong.

### Hand off to R2

Always. Fix-induced regressions are the #1 R2 finding class (Run 2:
3/7 BLOCKINGs were introduced BY the fixes).

---

## R2 — Audit the fixes (3 agents, parallel)

**Runs by default when Fix Phase ran.** Skip only with explicit
`--skip-r2` in pre-flight.

**Clean context for aligned + adversarial.** Both get NO R1 findings,
NO fix-phase output, NO session history — fresh audit of the post-fix
tree. This defeats fix-agent bias: the fix agent says "done"; R2 says
"actually, no." Fix verifier is the exception (below).

### Agents

Same two lenses as R1 + one agent with R1-findings context.

1. **Aligned reviewer** — post-fix conventions/architecture check
   (did a fix violate AGENTS.md or introduce an anti-pattern?)
   Receives branch name + AGENTS.md + `docs/patterns/*`. **Commit
   subjects withheld** — on a post-fix branch, "address review
   findings" commits frame the diff as "bugs already fixed" and
   leak the same bias the adversarial metadata-strip exists to
   prevent.

2. **Adversarial reviewer** — metadata-blind, same charter as R1.
   Catches regressions introduced by the fix, plus R1 recall gaps.

3. **Fix verifier** (`source_reviewer: fix_verifier`) — receives the
   R1 judge's findings list AND the post-fix diff. **Commit subjects
   withheld** — same rationale as aligned: post-fix commits like
   "address review findings" frame the diff as "bugs already fixed"
   and bias the verifier toward sycophantic agreement. For each R1
   finding, confirms:
   - The fix was applied
   - It addresses the root cause (not just the symptom)
   - No new issues in the fix's scope (no half-done sentinel fixes,
     no directionally-correct-but-incomplete patches)
   - **Scope is complete.** If the R1 finding flagged a pattern, the
     fix covered every grep-match of that pattern in `path_filter`,
     not just the named files. Run 2 evidence: `stageModelAction` fix
     was "directionally correct but incomplete" — callsites changed,
     root cause in `lib/utils/safe-action.ts` missed.

Each agent emits findings into a fresh judge pass (same §Judge process).

### Loop

If R2 judge emits findings → Fix Phase again → R2 again. Halt when R2
emits `clean`.

---

## Mandatory rules — apply to every agent

Include verbatim in every agent prompt:

```
Verification mandate:

Every finding must include `verification_command` — a shell / grep /
ast-grep command that proves the claim. The judge runs it; failing
commands drop the finding.

When you claim a third-party function "is dead code", "doesn't exist",
or "is never imported", READ the actual installed file at the expected
path. A failed grep is NOT proof of absence — symlinks, pnpm
content-addressed store, compiled output, TS path aliases, dynamic
imports, reflection, and interface dispatch hide code from grep.

Under-scoping: if you flag a pattern in one file, grep for all
instances in the `path_filter` before reporting. Flag the full set.

No recursion: do not dispatch further subagents.

Audit agents run in `permissionMode: plan` (read-only).
```

---

## Severity

- **BLOCKING** — runtime failure, security issue, data loss, invisible breakage
- **SHOULD-FIX** — correctness, type safety, test gaps, inconsistency
- **WATCH** — documented trade-offs, fragile patterns, scope concerns
- **NIT** — style, naming, cosmetic

---

## Finding schema

```json
{
  "severity": "BLOCKING | SHOULD-FIX | WATCH | NIT",
  "file": "src/path.ts",
  "line_start": 42,
  "line_end": 47,
  "message": "one-sentence actionable statement",
  "why": "1–2 sentences grounding the claim in the diff",
  "verification_command": "shell command that proves the claim",
  "source_reviewer": "aligned | adversarial | tests | fix_verifier",
  "category": "correctness | security | regression | perf | ..."
}
```

Judge adds on dedupe:

```json
{
  "high_confidence": true,
  "source_reviewer": "aligned+adversarial"
}
```

---

## Defense layer

Non-optional.

- **Cost cap:** $1.50/phase; abort + partial report on trip
- **Wall-clock cap:** 600s/phase; scale up for R2 and large diffs
- **Failure cap:** N consecutive tool failures → halt that agent;
  continue others
- **No recursion:** agents cannot dispatch further subagents
- **Read-only in audit phases:** `permissionMode: plan` (enforcement
  layer); optionally `disallowedTools: Write, Edit, NotebookEdit` as
  defense-in-depth
- **Inter-agent message rate:** halt if >10/min sustained 2min.
  Defense against the [$47k agent-loop case](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/).

---

## Prompt caching

Structure every reviewer call as:

```
[system prompt (shared)]
[AGENTS.md / docs/patterns/* — route by file extension]
[compressed diff]
<cache_control: ephemeral (5-min TTL)>
[per-reviewer lens + task]
```

Shared-prefix cache reads = 10% of base input
([Anthropic docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)).
Fire reviewers within the 5-min TTL. Per-lens tails and outputs are
uncached; total cost still scales with reviewer count on a smaller base.

---

## Iteration

Evidence lives in `multi-agent-pr-review.runs.md` (append-only, one
section per real run). Pending gaps, open questions, and unvalidated
hypotheses live there — NOT in this playbook. The playbook states
rules; the runs log captures why.

**Before proposing changes to this playbook:**

1. Read the last 3 runs. One run is an anecdote; a pattern across 2+
   is evidence.
2. Check §Pending in the runs log; cite the gap if your change
   targets one.
3. Require contradicting evidence before loosening a rule that was
   added from a specific run. Check the `changes this run produced`
   section first.

**When shipping a change:** if it resolves a pending gap, remove that
gap from the runs log in the same edit. If the change was driven by a
specific run, reference it in that run's `changes this run produced`
section.

**User-only data:** after each run, the user fills the `Fix-phase
outcome` field in the runs log. That's the only field the AI can't
infer alone, and it's needed to calibrate high-confidence precision
and severity accuracy.

---

## References

- `multi-agent-pr-review.runs.md` — append-only run log
- `multi-agent-code-review-reference.md` — full research backing
  (judge biases, confirmation-bias study, Qodo reflect-prompt, Sonnet
  vs Opus pricing, prompt-caching mechanics, failure modes). Citations
  verified via WebFetch where possible — see each section's caveats for
  claims that couldn't be automatically confirmed.
- `golden-set/` — regression-test fixtures with known bugs. Run
  `./golden-set/run.sh <fixture>` to set up a throwaway repo, then
  invoke this skill against it and compare findings to `expected.json`.
  Use this on every playbook change to catch drift empirically.
