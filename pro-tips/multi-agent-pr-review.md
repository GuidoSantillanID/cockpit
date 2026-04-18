# Multi-Agent PR Review with Judge Consolidation

Deploy subagents in parallel, each with a distinct review lens. They work
independently (wisdom of crowds — overlap is intentional, deduplication
happens at judge phase).

---

## Round 1 — Initial Audit (4 agents)

### Agent 1 — Standards & Architecture

Use `superpowers:code-reviewer` agent.

- Project conventions compliance (read AGENTS.md files)
- Architectural violations or anti-patterns introduced
- Workaround quality — clean or hacky?
- Code quality, consistency, naming

### Agent 2 — Process & CI Readiness

Use `superpowers:requesting-code-review` skill.

- Uncommitted changes, WIP markers, stash
- Tests passing (use project test commands)
- TODO/FIXME/HACK comments introduced
- Files that shouldn't be committed (env, debug logs, secrets)
- Branch cleanliness, CI readiness

### Agent 3 — Structured PR Review

Use `/review-pr` skill.

- Categorize changed files by review priority
- Identify highest-risk changes
- Detect AI code red flags (overengineered solutions, unnecessary abstractions)
- Flag what needs the most careful human review

### Agent 4 — Deep Regression Review

General-purpose agent. Most critical.

Read all AGENTS.md files, full diff against base branch, lockfiles, package.json
changes.

**[CUSTOMIZE THESE]** Focus areas based on what was upgraded:

- **Framework**: config changes, behavioral changes, API renames
- **Styling**: class name changes, config format migration, plugin breakage
- **Auth**: SDK API changes, session handling, middleware, callback URLs
- [Add more deps as needed]

Additional checks:

- Lockfile verification: are vulnerable versions actually gone from transitive deps?
- Fragile workarounds that'll break on next minor bump
- Silent runtime failures: compiles fine, fails at runtime
- Overengineered or "extremely AI" solutions — flag unnecessary complexity
- Organize findings as: **BLOCKING** / **SHOULD-FIX** / **WATCH** / **VERIFIED OK**

---

## Judge Phase

Run after all agents complete.

- Deduplicate findings across all agents
- Categorize by severity: blocking > should-fix > nit
- Flag disagreements between agents
- Present everything organized — **make no decisions**, user decides
- If multiple agents independently flag the same issue, mark it as high-confidence

---

## Fix Phase (after judge report)

Launch dev agents for actionable findings, paired with review agents:

- **Dev agent** implements the fix
- **Review agent** (launched after dev completes) verifies: correct fix, no
  collateral damage, no missed instances
- Run tests after all fixes to catch regressions from the fixes themselves
- **Before acting on any finding about third-party SDK behavior**: launch a
  research agent to verify the claim by reading the actual installed code.
  Do NOT trust the original finding alone.

---

## Round 2 — Verification Audit (5 agents, clean context)

Run AFTER round 1 fixes are applied. These agents get NO context from round 1
— they start fresh and independently verify the full diff.

### Agent A — Auth / Security Flow Integrity

- Trace the full auth flow end-to-end
- Verify every `process.env` read — is it justified or should it use validated env?
- For any side effect on `process.env`, verify necessity by reading actual SDK source
- Check cookie handling, session maintenance, redirect safety

### Agent B — Runtime Correctness

- Silent runtime failures (compiles but crashes)
- Config validity for the target framework version
- Schema/transform behavior changes in upgraded libs
- Import correctness (v3 names that were renamed in v4)
- `process.env` vs validated env object audit

### Agent C — SDK Contract Verification

- For each upgraded package: read the actual installed `.js` and `.d.ts` files
- Verify constructor options, method signatures, return types match usage
- Check peer dependency compatibility
- Verify TypeScript compilation passes

### Agent D — Test Coverage Gap Finder

- Run the actual test suite, report results
- For each changed behavior, check if a test covers it
- Identify what's NOT tested that SHOULD be
- Check for test mocks that don't match actual behavior

### Agent E — Adversarial Reviewer

- Assume nothing is correct. Find mistakes.
- Do NOT trust code comments — verify every claim
- Be extra skeptical of recent commits from the current session
- Hunt for: wrong comments, missed migrations, stale workarounds, import-order
  dependencies, AI-generated code that wasn't properly reviewed

---

## Mandatory Instructions for ALL Agents

Include this block in every agent prompt:

```
CRITICAL INSTRUCTION: When you make claims about third-party packages,
you MUST read the actual installed code in node_modules. Do NOT trust
grep results alone — grep can miss files due to path issues, symlinks,
or scoping.

- A failed grep is NOT proof of absence. READ the actual file.
- If you claim "function X is dead code" or "function X doesn't exist",
  you must PROVE it by reading the file where it should be.
- If you claim a function is "never imported", you must search the
  COMPILED output (dist/), not just the source (src/).
- False claims about third-party SDKs can cause production outages.
```

---

## Severity Definitions

Include in every agent prompt to prevent over-classification:

- **BLOCKING** = runtime failure, security issue, data loss, invisible breakage
- **SHOULD-FIX** = correctness, type safety, test gaps, inconsistency
- **WATCH** = documented tradeoffs, fragile patterns, scope concerns
- **NIT** = style, naming, cosmetic

---

## Key Principles

- All agents are read-only in audit phases — no changes
- Infer branch purpose from branch name + diff (no ticket required)
- Solutions shouldn't be overengineered; flag anything that smells like
  over-abstraction
- Challenge everything, including your own subagents' findings
- **Never act on a single agent's claim about third-party code** — require
  verification from a second source (another agent, research agent, or
  manual reading)
- Question findings before acting — false positives happen, and acting on
  a false positive can introduce bugs worse than the original issue

## Customization Points

1. Replace the dep-specific focus areas in Agent 4 with whatever you upgraded
2. Add nervous areas (e.g., "auth flows feel fragile")
3. If you have a ticket description, feed it to the agents for better context
4. Adjust round 2 agent count based on risk — 5 is thorough, 3 is minimum

---

## Lessons Learned

### Round 1 (initial audit)

- **Wisdom of crowds works**: findings flagged by 2+ agents were all real
- **Distinct lenses find unique issues**: each agent found things others missed
- **Dev + review agent pattern**: cheap insurance for fix correctness
- **Judge phase is essential**: caught 3 severity over-classifications
- **Agent 4 (Deep Regression) is the MVP**: found both blockers no other agent
  caught. If budget-limited, run this one.
- **Agent 3 (PR Review Guide) has weakest signal-to-noise**: consider replacing
  with a second deep-review agent or running it first and feeding its file
  prioritization to other agents
- **Always verify before acting**: a "missing test" finding was a false positive
  (tests existed), and a "wrong default type" fix was itself wrong (Zod v4
  defaults bypass transforms, so the original code was correct)

### Round 2 (verification audit) — why it's necessary

A round 1 research agent claimed a third-party SDK function was "dead code —
defined but never imported." Three independent round 2 agents confirmed it was
alive and actively used by 5 internal modules. The difference: round 2 agents
were explicitly told to READ the actual installed files, not trust grep.

Acting on the false "dead code" claim led to removing a necessary `process.env`
side effect. The removal was caught and reverted before merge, but only because
the user questioned the change and triggered deeper investigation.

**Key takeaway**: A research agent's grep returning no results does NOT mean the
code doesn't exist. Symlinks, pnpm store paths, compiled output directories,
and glob patterns can all cause grep to miss real code. Always verify by reading
the actual file at the expected path.

### Round 2 agent design improvements

- **Clean context**: no session history, no prior findings, no bias
- **Adversarial agent**: explicitly told to assume nothing is correct
- **SDK contract verifier**: must read actual `.js` and `.d.ts` files
- **"Prove it" mandate**: every claim about third-party behavior must be backed
  by reading the actual installed code, not grep or documentation
- **Test runner**: actually executes tests, doesn't just read them

### Performance data

| Phase | Agents | Wall-clock | Coverage |
|-------|--------|------------|----------|
| Round 1 audit | 4 | ~20 min | Found 2 blockers, 7 should-fix, 7 watch |
| Round 1 fixes | 2 dev + 2 review | ~5 min | All fixes verified |
| Research agents | 4 | ~2-6 min each | Prevented 2 bad fixes, 1 was wrong |
| Round 2 audit | 5 | ~30 min | Found 2 new production risks, confirmed all fixes |
| Total | ~15 agents | ~1 hour | Comprehensive for 190-file diff |
