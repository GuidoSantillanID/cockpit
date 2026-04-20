# Multi-Agent PR Review with Judge Consolidation

> Upgraded April 17, 2026 with findings from `multi-agent-code-review-reference.md`.
> External-sources fact-check pass: April 18, 2026.
> Same 2-round audit → judge → fix → verify shape as v1; agent roles, judge mechanics,
> and defense layer updated with research from HubSpot Sidekick, Qodo, Greptile,
> Anthropic Code Review, and academic work on LLM-as-judge and confirmation bias.

Deploy subagents in parallel, each with a distinct review lens. They work
independently (wisdom of crowds — overlap is intentional, deduplication
happens at Judge phase).

---

## Run envelope

Target for a typical branch (<50 changed files):

- **Cost:** ~$0.30–0.80 per full run with prompt caching; ceiling $1.50
- **Wall-clock:** Round 1 ~3–6 min, judge ~30s–2min, Round 2 ~15–30 min if run
- **Hard caps (per phase, not per pipeline):** abort Round 1 on `cost_usd >= 1.50`
  or `wall_clock_sec >= 600`. Round 2 runs under its own envelope (larger).
  Do not set a single pipeline-wide 10-min cap — the Performance table below
  reports ~1 hour for a 190-file diff across all phases.

Most PRs need only Round 1 + judge. Run Round 2 when stakes are high (auth, dep
upgrades, production-critical paths, large diffs). Scale caps up proportionally
for diffs over 50 files.

**Per-agent file cap (rule of thumb).** Target **≤ 50 files per agent**. The
600s no-progress watchdog and ~10-min stream-idle ceiling are real limits; a
reviewer working through a very large diff is more likely to bump into them,
and a stall mid-review wastes the entire agent's budget. Split BEFORE dispatch
rather than hoping the agent copes:

- **Preferred:** chunk by directory or feature slice (e.g., `app/api/**`,
  `features/fine-tuning/**`). Each chunk keeps the same reviewer lens; the
  judge merges findings across chunks by `source_reviewer`.
- **Fallback:** chunk by file-type (routes, components, tests) when the diff
  has no clear directory structure.
- **Do NOT** chunk by reviewer lens alone — that's orthogonal to file count and
  doesn't reduce any single agent's load.

Record the chunking plan in the envelope under `scope` (see §Envelope schema)
so a future reader knows what each agent actually saw.

---

## Round 1 — Initial Audit (default: 3 agents; Agent 3 optional)

Dispatched in parallel. **Fire all within a 5-min window** to hit the warm prompt
cache (shared prefix ≈ system + AGENTS.md + compressed diff; cache reads cost 10%
of base input on the shared prefix per Anthropic — per-reviewer lens prompts and
outputs remain uncached, so total cost still scales with reviewer count, just on
a smaller base).

Default roster: Agents 1, 2, 4 (required) + Agent 3 (optional, see note below).

### Agent 1 — Standards & Architecture (`source_reviewer: standards`)

Use `superpowers:code-reviewer` agent. **Receives intent context** (branch name,
commit subjects, ticket).

- Project conventions compliance (read AGENTS.md, `docs/patterns/*`)
- Architectural violations or anti-patterns introduced
- Workaround quality — clean or hacky?
- Code quality, consistency, naming

`verification_command` **REQUIRED** per the universal mandate (see §Mandatory Instructions).

### Agent 2 — Process & CI Readiness (`source_reviewer: process`)

Use `superpowers:requesting-code-review` skill. **Receives intent context.**
Bash-capable.

- Uncommitted changes, WIP markers, stash
- **Detect and run** the project's test command (priority: `package.json scripts.test` → `pyproject.toml` → `Makefile` → `justfile` → direct runners). Cap at 180s. Live signal matters — do not just read tests.
- TODO/FIXME/HACK comments introduced
- Files that shouldn't be committed (env, debug logs, secrets)
- Branch cleanliness, CI readiness

`verification_command` **REQUIRED** for every finding (test-failure findings must include the exact command that reproduces the failure).

### Agent 3 — Structured PR Review (OPTIONAL; `source_reviewer: structured`)

Use `/review-pr` skill. **Receives intent context.**

- Categorize changed files by review priority (CRITICAL / HIGH / MEDIUM / SKIP)
- Identify highest-risk changes
- Detect AI code red flags (overengineered solutions, unnecessary abstractions)
- Flag what needs the most careful human review

`verification_command` **REQUIRED** per universal mandate.

**Status:** optional. Historically this lens has the weakest signal-to-noise.
Two viable ways to use it: (a) run it FIRST and feed its file prioritization
to Agents 1, 2, 4 as pre-context, or (b) skip entirely. Do not run it as a
peer alongside the others — its output overlaps with the standards and
regression lenses without adding much.

### Agent 4 — Deep Regression Review (`source_reviewer: regression`)

General-purpose agent. **Empirically the MVP across repeated use — if
budget-limited, run this one and the judge.**

**Receives compressed diff only. NO intent context.** This is the confirmation-bias
defense: framing a diff as "bug-free" drops vulnerability detection 16–93%
across the four models tested ([arXiv 2603.18740](https://arxiv.org/html/2603.18740)).
Metadata redaction plus explicit de-biasing instructions restores detection in
all interactive cases and **94%** of autonomous cases.

Reads AGENTS.md files, compressed diff, lockfiles, `package.json` changes.

**[CUSTOMIZE]** Focus areas based on what was upgraded:

- **Framework:** config changes, behavioral changes, API renames
- **Styling:** class-name changes, config-format migration, plugin breakage
- **Auth:** SDK API changes, session handling, middleware, callback URLs
- [Add more deps as needed]

Additional checks:

- Lockfile verification: are vulnerable versions actually gone from transitive deps?
- Fragile workarounds that'll break on next minor bump
- Silent runtime failures: compiles fine, fails at runtime
- Overengineered or "extremely AI" solutions — flag unnecessary complexity

`verification_command` **REQUIRED** for every finding (third-party claims must
back up via reading the installed file). A failed grep is NOT proof of absence —
symlinks, pnpm content-addressed store, compiled/transpiled output, TypeScript
path aliases, dynamic imports, reflection, and interface dispatch all hide code
from grep. READ the installed file at the expected path.

Organize findings as: **BLOCKING / SHOULD-FIX / WATCH / NIT** (see §Severity Definitions).

---

## Judge Phase

Run after all Round 1 agents complete.

**Model:** Sonnet, not Opus. Sonnet 4.6 scores 79.6% on SWE-bench Verified vs
Opus 4.6 at 80.8% — a 1.2-point gap on raw benchmark, at ~60% of Opus per-token
cost (Sonnet $3 / $15 vs Opus $5 / $25 input/output; both ratios are 0.6).
Effective cost drops further with prompt caching on the shared prefix (cache
reads = 10% of base input) and the judge's small pre-filtered input, but the
per-token ratio is the anchor — don't claim savings the arithmetic doesn't
support. Opus-as-judge is overkill once input is pre-filtered and reviewers
have done the heavy lifting.

**Temperature:** 0.2–0.3 (default 0.25) — low temperature for calibration
stability. The specific point value is a pragmatic default, not an empirically
tuned optimum.

**Input:** reviewer findings JSON only. **Strip PR metadata** — no branch name,
no commit messages, no ticket, no author. Reviewers needed intent; the judge
must not see it (same confirmation-bias defense as Agent 4).

**Process (in order):**

1. **Verification pass.** `verification_command` is required on every finding
   (see §Mandatory Instructions). Drop any finding missing one with reason
   `missing_verification_command`. For every remaining finding: run the command.
   If it fails (non-zero exit, empty output, or contradicts the claim), drop
   with reason `verification_failed`.

   Note: the judge needs a checked-out working tree to run these commands. If
   the judge is deployed as a JSON-only plan-mode agent without shell access,
   delegate the verification pass to a dedicated read-only subagent (the rest
   of the judge flow — filtering, capping, promotion — runs on JSON alone).

2. **HubSpot 3-criteria filter** — all three must pass:
   - **Succinct** — can a busy engineer act on it without re-reading?
   - **Accurate** — technically correct, grounded in the diff?
   - **Actionable** — concrete fix, not hand-wringing?

3. **Hard category caps** (adapted from Qodo `pr_code_suggestions_reflect_prompts.toml`
   — deterministic ceilings beat asking the judge to "be strict"). Qodo uses a
   0–10 numeric score; this doc uses BLOCKING/SHOULD-FIX/WATCH/NIT throughout,
   so caps are translated to that vocabulary:
   - **Cap at SHOULD-FIX** (cannot promote higher): generic error-handling or
     type-checking suggestions without a concrete failure mode
   - **Cap at WATCH**: "verify X" suggestions without a concrete claim to verify
   - **Cap at WATCH**: finding's proposed change is cosmetic or tautological relative to the existing code (no behavior difference)
   - **DROP** (route to `dropped` with reason `category_cap`): type-hint-only,
     docstring-only, unused-import-only, "use more specific exception types"

4. **High-confidence promotion.** If ≥2 agents independently flagged the same
   file/line with compatible messages, mark `high_confidence: true`.

5. **Severity assignment** per §Severity Definitions.

6. **Output (JSON envelope)** — the schema below, OR — if zero findings pass
   the bar — `{"status": "clean", "verdict": "Ready", "summary": "clean, ship it", ...}`.
   **Silence is a feature** (HubSpot: "often leaving no comments at all"
   correlates with 80%+ engineer approval). The envelope is the canonical
   artifact; step 7 below turns it into something a human can read.

```json
{
  "status": "findings" | "clean",
  "verdict": "Ready" | "Needs Attention" | "Needs Work",
  "summary": "one line",
  "scope": {
    "base": "origin/main",
    "head": "HEAD",
    "path_filter": "components/web/**",
    "files_changed": 148,
    "chunks": [
      { "agent": "standards", "paths": ["app/api/**"], "files": 42 },
      { "agent": "regression", "paths": ["features/**"], "files": 61 }
    ]
  },
  "rounds_run": ["R1"] | ["R1", "R2"],
  "skipped_agents": [
    { "agent": "A (auth)", "reason": "no auth/session/middleware changes in diff" },
    { "agent": "D (CI)", "reason": "Agent 2 already ran tests clean; no duplicate needed" }
  ],
  "findings": [ /* full finding objects per §Finding schema */ ],
  "dropped": [
    {
      "original": { /* full finding object per §Finding schema */ },
      "reason": "missing_verification_command | verification_failed | category_cap | not_succinct | not_accurate | not_actionable"
    }
  ]
}
```

`scope`, `rounds_run`, and `skipped_agents` are mandatory when non-default.
They make the envelope self-describing so a future reader (or the Fix Phase
agents) can tell what was actually audited vs. assumed-safe.

7. **Human-readable rendering.** The JSON envelope is the canonical artifact
   (consumed by Fix Phase dev/review agents, programmatic filtering, dedup).
   It is **not** the primary deliverable to the human reviewer — raw JSON is
   noise to read. After emitting the envelope, render a short markdown summary
   for the user, alongside the JSON:

   ```markdown
   **Verdict:** Needs Work — 2 BLOCKING, 5 SHOULD-FIX, 3 WATCH, 1 NIT
   **Scope:** components/web/** (148 files, 2 chunks) · R1+R2 · skipped: A, D

   ### BLOCKING
   - `app/api/fine-tuning/runs/route.ts:19` — case-sensitive keyword search regression (`high_confidence`, regression+sdk)
   - `app/api/fine-tuning/upload/route.ts:7` — no null guard on jobId/uploadId (`high_confidence`, runtime+sdk+adversarial)

   ### SHOULD-FIX
   - `app/api/fine-tuning/complete-upload/route.ts:23` — catch returns implicit HTTP 200 on failure
   - ...

   ### Dropped (11)
   2 verification_failed BLOCKINGs, 4 category_cap, 5 not_actionable — see JSON for details.
   ```

   Rules for the markdown:
   - One line per finding: `` `file:line` — one-sentence message (tags) ``
   - Group by severity descending; omit empty sections
   - Tags: `high_confidence`, `source_reviewer` values (comma-separated)
   - Dropped findings: summarize by reason count, don't list individually
   - Keep under ~40 lines for a typical PR — scannable in one screen

   The JSON envelope stays in the response (collapsed or below the markdown)
   so Fix Phase agents and future automation still have the structured form.

---

## Fix Phase (after judge report)

Launch dev + review pairs per actionable BLOCKING / SHOULD-FIX finding:

- **Dev agent** implements the fix, scoped to the exact file:line
- **Review agent** (after dev) verifies: correct fix, no collateral damage, no missed instances
- Run tests after all fixes to catch regressions introduced BY the fixes
- **Before acting on any finding about third-party SDK behavior:** launch a
  research agent to re-verify by reading the actual installed code. Do NOT trust
  the original finding alone. (This is why `verification_command` is mandatory.)

---

## Round 2 — Verification Audit (5 agents, clean context)

Run AFTER Round 1 fixes are applied. **Run when stakes are high** — not every PR.

Round 2 agents get **NO** context from Round 1 — fresh context, independent
verification. Mitigates LLM-judge brittleness: [arXiv 2506.09443](https://arxiv.org/abs/2506.09443)
(RobustJudge, "LLMs Cannot Reliably Judge (Yet?)") documents up to 40% output variance
across prompt templates and systematic vulnerabilities to prompt-level adversarial
attacks. A fresh-context second pass is the practical defense.

All Round 2 agents: `verification_command` **REQUIRED** on every finding per
§Mandatory Instructions. Intentional lens overlap (Agents B/C/E all touch
third-party behavior) is a wisdom-of-crowds feature, not a bug — each finds it
through a different verification path.

### Agent A — Auth / Security Flow Integrity (`source_reviewer: auth`)

Scope: auth-flow semantics only. Leaves SDK signature checks to C, runtime
validity to B.

- Trace the full auth flow end-to-end
- Verify every `process.env` read — is it justified or should it use validated env?
- For any side effect on `process.env`, verify necessity by reading actual SDK source
- Check cookie handling, session maintenance, redirect safety

### Agent B — Runtime Correctness (`source_reviewer: runtime`)

Scope: "does it actually run?" — execution-path behavior, not contracts. Leaves
static API signature verification to C.

- Silent runtime failures (compiles but crashes)
- Config validity for the target framework version
- Schema/transform behavior changes in upgraded libs at runtime
- `process.env` vs validated env object audit

### Agent C — SDK Contract Verification (`source_reviewer: sdk`)

Scope: static contracts only — types, signatures, imports. Leaves runtime
behavior to B.

- For each upgraded package: read the actual installed `.js` and `.d.ts` files
- Verify constructor options, method signatures, return types match usage
- Import correctness (v3 names that were renamed in v4)
- Check peer dependency compatibility
- Verify TypeScript compilation passes

### Agent D — Test Coverage Gap Finder (`source_reviewer: coverage`)

- Run the actual test suite, report results
- For each changed behavior, check if a test covers it
- Identify what's NOT tested that SHOULD be
- Check for test mocks that don't match actual behavior

### Agent E — Adversarial Reviewer (`source_reviewer: adversarial`)

**Metadata-blind.** No branch name, no commits, no ticket.

- Assume nothing is correct. Find mistakes.
- Do NOT trust code comments — verify every claim
- Be extra skeptical of recent commits from the current session
- Hunt for: wrong comments, missed migrations, stale workarounds, import-order dependencies, AI-generated code that wasn't properly reviewed
- `verification_command` **REQUIRED** for every finding

---

## Mandatory Instructions for ALL Agents

Include this block in every agent prompt:

```
CRITICAL — Verification mandate:

When you make claims about third-party packages, you MUST read the actual
installed code in node_modules (or the provider's install path). Do NOT
trust grep results alone — grep can miss files due to symlinks, pnpm
content-addressed store, compiled/transpiled output, TypeScript path
aliases, dynamic imports, reflection, or interface dispatch.

- A failed grep is NOT proof of absence. READ the actual file at the expected path.
- If you claim "function X is dead code" or "function X doesn't exist", PROVE it
  by reading the file where it should be.
- If you claim a function is "never imported", search the COMPILED output (dist/),
  not just the source (src/).
- False claims about third-party SDKs can cause production outages.

Every finding MUST include a `verification_command` — a shell/grep/ast-grep
command that proves the claim. Findings without `verification_command` will
be dropped by the judge.
```

---

## Severity Definitions

Include in every agent prompt to prevent over-classification:

- **BLOCKING** — runtime failure, security issue, data loss, invisible breakage
- **SHOULD-FIX** — correctness, type safety, test gaps, inconsistency
- **WATCH** — documented trade-offs, fragile patterns, scope concerns
- **NIT** — style, naming, cosmetic

---

## Finding schema

Every agent emits JSON findings:

```json
{
  "severity": "BLOCKING | SHOULD-FIX | WATCH | NIT",
  "file": "src/path/to/file.ts",
  "line_start": 42,
  "line_end": 47,
  "message": "one-sentence actionable statement",
  "why": "1-2 sentences grounding the claim in the diff",
  "verification_command": "shell command that proves the claim",
  "source_reviewer": "standards | process | structured | regression | auth | runtime | sdk | coverage | adversarial",
  "category": "correctness | security | regression | perf | ..."
}
```

Post-judge, each surviving finding is a superset of the agent schema, with
the judge adding:

```json
{
  "high_confidence": true,
  "source_reviewer": "standards+regression"
}
```

`high_confidence` is set when ≥2 agents independently flagged compatible
messages on the same file/line (see §Judge Phase, step 4).
`source_reviewer` becomes
a `+`-joined list of the original reviewers that raised the finding.

---

## Prompt caching layout

Every Round 1 reviewer call should be structured as:

```
[system prompt (shared)]
[AGENTS.md / docs/patterns/* — route by file extension]
[compressed diff]
<cache_control: ephemeral (5-min TTL)>
[per-reviewer lens prompt]
[task instruction]
```

Cache reads on the shared prefix are 10% of base input cost
([docs.anthropic.com/prompt-caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)).
Per-reviewer lens prompts, task instructions, and outputs are uncached and
scale linearly with reviewer count. Fire all reviewers within the 5-min TTL
to hit warm cache. Published savings: up to 90% input cost reduction on the
shared-prefix portion.

---

## Defense layer

Hard protections — not optional:

- **Cost cap:** `max_cost_usd` per phase, default 1.50 (caps apply per Round, not pipeline-wide — see Run envelope). Abort + emit partial report on trip.
- **Wall-clock cap:** `max_wall_clock_sec` per phase, default 600 (10 min for Round 1; scale up for Round 2 and large diffs).
- **Failure cap:** N consecutive tool failures per agent → halt that agent, continue others.
- **No recursion:** agents cannot dispatch further subagents. Defends against the [$47k agent-loop case](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/) (11 days of ping-pong, no stop condition).
- **Read-only in audit phases:** `permissionMode: plan` — this is what actually enforces read-only at the permission layer. Optionally add `disallowedTools: Write, Edit, NotebookEdit` as defense-in-depth, but rely on plan mode; allow/disallow lists alone are not a substitute.
- **Message-exchange anomaly monitor:** if inter-agent messages exceed 10/min sustained 2min, halt.

---

## Key Principles

- All agents are read-only in audit phases — no changes
- Infer branch purpose from branch name + diff (no ticket required) — reviewers get it, the judge does not
- Solutions shouldn't be overengineered; flag anything that smells like over-abstraction
- Challenge everything, including your own subagents' findings
- **Never act on a single agent's claim about third-party code** — require verification from a second source (`verification_command`, another agent, or manual reading)
- Question findings before acting — false positives happen, and acting on one can introduce bugs worse than the original
- **Silent output is valid.** If the judge emits `clean, ship it`, believe it.
- **Prefer a different model family for the judge than for reviewers** if
  cross-provider is possible (via MCP / adapter). LLM-judge robustness is
  brittle: [arXiv 2506.09443](https://arxiv.org/abs/2506.09443) (RobustJudge)
  reports up to 40% output variance across prompt templates and documented
  systematic attack vulnerabilities. Anthropic-only (the expected default for
  this doc): use a distinct judge system prompt and strip metadata — this is
  the pragmatic fallback, not the preferred architecture.

---

## Customization Points

1. Replace the dep-specific focus areas in Agent 4 with whatever you upgraded
2. Add nervous areas (e.g., "auth flows feel fragile")
3. If you have a ticket description, feed it to reviewers (NOT the judge)
4. Adjust Round 2 agent count based on risk — 5 thorough, 3 minimum (keep C, D, E)
5. Skip Round 2 entirely for low-risk PRs
6. Tighten the `max_cost_usd` / `max_wall_clock_sec` caps for smaller runs

---

## Lessons Learned

### Round 1

- **Wisdom of crowds works:** findings flagged by 2+ agents were all real → automatic high-confidence promotion at the judge.
- **Distinct lenses find unique issues:** each agent found things others missed.
- **Dev + review agent pattern:** cheap insurance for fix correctness.
- **Judge phase is essential:** caught 3 severity over-classifications in one run; external corroboration (HubSpot, Greptile) in §Research anchors.
- **Agent 4 (Deep Regression Review) is the MVP:** found both blockers no other agent caught. If budget-limited, run this one and the judge.
- **Agent 3 (Structured PR Review) has weakest signal-to-noise:** consider running first and feeding its file prioritization to other agents, or replacing with a second deep-review agent.
- **Always verify before acting:** a "missing test" finding was a false positive (tests existed); a "wrong default type" fix was itself wrong (Zod v4 defaults bypass transforms, so the original code was correct). The `verification_command` mandate exists because of these.

### Round 2 — why it's necessary

A Round 1 research agent claimed a third-party SDK function was "dead code — defined but never imported." Three independent Round 2 agents confirmed it was alive and actively used by 5 internal modules. Root cause: the original agent relied on grep, which missed files due to symlinks, pnpm content-addressed store, and compiled output directories.

Acting on the false "dead code" claim led to removing a necessary `process.env` side effect. The removal was caught and reverted before merge, but only because the user questioned the change.

**Key takeaway:** a grep returning no results does NOT mean the code doesn't exist. Always verify by reading the actual file at the expected path. This is why `verification_command` is mandatory.

### Round 2 agent design

- **Clean context:** no session history, no prior findings, no bias
- **Adversarial agent:** explicitly told to assume nothing is correct; metadata-blind
- **SDK contract verifier:** must read actual `.js` and `.d.ts` files
- **"Prove it" mandate:** every claim about third-party behavior backed by reading the actual installed code, not grep or documentation
- **Test runner:** actually executes tests, doesn't just read them

### Research anchors (April 2026)

From `multi-agent-code-review-reference.md`:

- **Judge pattern is the #1 signal lever.** HubSpot Sidekick: 80%+ approval and 90% reduction in time-to-first-feedback ([HubSpot blog](https://product.hubspot.com/blog/automated-code-review-the-6-month-evolution)). Greptile: 19% → 55%+ addressed rate in 2 weeks ([ZenML case study](https://www.zenml.io/llmops-database/improving-ai-code-review-bot-comment-quality-through-vector-embeddings)). Anthropic built-in: 16% → 54% substantive reviews (internal research, unverified externally).
- **Confirmation bias is measurable and large:** framing a diff as "bug-free" drops detection 16–93% ([arXiv 2603.18740](https://arxiv.org/html/2603.18740)). Metadata redaction + instructions recovers 94%. Hence the metadata strip for Agent 4, Agent E, and the judge.
- **Qodo's reflect prompt** is the only fully-published production judge prompt ([github.com/qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent/blob/main/pr_agent/settings/code_suggestions/pr_code_suggestions_reflect_prompts.toml)). Hard category caps (originally 0–10 score ceilings) adapted into the BLOCKING/SHOULD-FIX/WATCH/NIT vocabulary used throughout this doc.
- **CodeRabbit verification pattern:** "comments come with receipts" — tool-based proof accompanying every finding. The `verification_command` requirement is derived from that.
- **Sonnet-as-judge matches Opus-as-judge** on pre-filtered input. 1.2pt SWE-bench gap at ~60% of Opus per-token cost (further reduced by prompt caching and the judge's small pre-filtered input).
- **Prompt caching saves up to 90%** on repeated prefix tokens. Fire reviewers within 5-min TTL.
- **Hard cost/time caps are existential:** the [$47k agent-loop case](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/) — 11 days of agent ping-pong, no stop condition.
- **Independent benchmarks stress frontier accuracy:** SWE-PRBench (350 PRs, 8 models) reports 15–31% bug-detection across frontier models; Martian Code Review Bench (17 tools, 200k+ PRs, March 2026) reports F1 ≈50–52% for the top commercial review bots (CodeRabbit 51.2%, CodeAnt 51.7%). Vendor-quoted sub-1% false-positive rates don't survive either benchmark. See `multi-agent-code-review-reference.md` for source URLs.

### Performance data

*Single run on a 190-file diff. For typical <50-file branches, scale wall-clock to the Run envelope at top of doc (~3–6 min Round 1, ~15–30 min Round 2).*

| Phase | Agents | Wall-clock | Coverage |
|-------|--------|------------|----------|
| Round 1 audit | 4 (Agents 1+2+3+4; Agent 3 included in this run) | ~5–20 min | Found 2 blockers, 7 should-fix, 7 watch |
| Judge | 1 | ~30s–2min | Filtered noise; flagged 3 over-classifications |
| Fix phase | 2 dev + 2 review | ~5 min | All fixes verified |
| Research agents (pre-act checks) | 4 | ~2–6 min each | Prevented 2 bad fixes; 1 fix was itself wrong |
| Round 2 audit | 5 | ~30 min | Found 2 new production risks, confirmed all fixes |
| **Total** | **~15 agents** | **~1 hour** | **Comprehensive for 190-file diff** |

---

## References

- `multi-agent-code-review-reference.md` — encyclopedia with full evidence backing every choice
- [HubSpot Sidekick evolution](https://product.hubspot.com/blog/automated-code-review-the-6-month-evolution)
- [Qodo pr-agent reflect prompt (verbatim)](https://github.com/qodo-ai/pr-agent/blob/main/pr_agent/settings/code_suggestions/pr_code_suggestions_reflect_prompts.toml)
- [Greptile embedding filter case study](https://www.zenml.io/llmops-database/improving-ai-code-review-bot-comment-quality-through-vector-embeddings)
- [Confirmation bias in LLM security review](https://arxiv.org/html/2603.18740)
- [$47k agent-loop case](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/)
- [Anthropic prompt caching docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
