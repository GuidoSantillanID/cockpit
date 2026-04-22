# Multi-Agent PR Review — Dogfood Runs Log

Append-only record of real runs. One section per run, newest at the bottom.
Source of evidence for tuning the playbook and skill. See
`multi-agent-pr-review.md` → §Iteration.

**Template (copy-paste for each new run):**

```markdown
## Run: YYYY-MM-DD — <repo> <pr-or-branch>

**Scope:** `<path_filter>` · N files · pipeline: R1 | R1+Fix+R2 | R1+Fix+R2+Fix+R2
**Pass type:** R1 (fresh) | R2 (post-fix) — detected via `git log --grep="address.*review.*findings"`
**Agents dispatched:**
  - R1: aligned×N, adversarial×N, tests×N
  - R2: aligned×N, adversarial×N, fix_verifier×N
**Chunked:** yes/no — why (files per chunk, or "single chunk" / "user override")
**Verdict:** X BLOCKING, Y SHOULD-FIX, Z WATCH, W NIT · N_raw → N_kept (drop%)
**Wall clock:** R1 ~Xmin, judge Xm Ys[, Fix ~Xmin, R2 ~Xmin, judge Xm Ys] · total ~Xmin
**Budget:** per phase from `envelope.budget_spent_usd` (R1 $X.XX, judge $X.XX, Fix $X.XX, R2 $X.XX)
**Fix-phase outcome:** [filled in post-fix] of N BLOCKINGs, M confirmed real, K false positives

### What worked
- ...

### What didn't
- ...

### Playbook/skill changes this run produced
- ...

### Open questions for next run
- ...
```

---

## Run: 2026-04-19 — genomics-product GP-1167 (first dogfood)

**Scope:** `components/web/**` · ~148 files · rounds: R1+R2
**Agents dispatched:** standards×1, regression×1, process×1 (unchunked);
Agent 3 (structured) skipped as redundant with standards+regression
**Chunked:** no — single-agent-per-lens against full 148-file scope
**Verdict:** numbers not captured precisely; ≥2 BLOCKING confirmed
(case-sensitive keyword search at `app/api/fine-tuning/runs/route.ts:19`;
unguarded `jobId`/`uploadId` at `app/api/fine-tuning/upload/route.ts:7`),
plus SHOULD-FIX and WATCH tier findings across the diff.
**Wall clock:** not captured · **Budget:** unmeasured (gap #3)
**Fix-phase outcome:** confirmed — both BLOCKINGs were addressed in follow-up
commit (bab08177d "address multi-agent PR review findings"). No explicit
"real vs false-positive" tally beyond the fix.

### What worked
- Running standards + regression + process in parallel found real bugs the
  user had not spotted in self-review.
- Metadata-blind regression lens (Agent 4) earned its keep — it caught at
  least one of the BLOCKINGs the standards lens missed.

### What didn't
- Invocation via free-form "review this PR using the strategy in XXX.md"
  left pre-flight implicit; scope, rounds, budget cap all inferred.
- Mid-run pause (user stepped away ~32 min) caused Agents 1 & 4 to appear
  "stalled" — actually idle-timeout on the stream, not a capacity problem.
  Misdiagnosed as a 148-file scope limit at first.
- Judge emitted JSON envelope without a human-readable summary; raw JSON
  was unusable for the user.
- No record of which agent lens flagged which finding → hard to verify
  high-confidence promotion logic.

### Playbook/skill changes this run produced
- Added pre-flight checklist (base, head, path_filter, files_changed,
  rounds, agents, chunks, budget_cap_usd) as MANDATORY.
- Added §Chunking rule (originally "≤50 files/agent"; later relaxed — see
  Run 2).
- Expanded envelope schema with `scope`, `rounds_run`, `skipped_agents`.
- Added Judge step 7: human-readable markdown rendering alongside JSON.
- Added "do not accept partial output from paused-then-resumed agent —
  re-dispatch with narrower scope" rule.
- Created `/review-multi-agent` skill wrapper.

### Open questions for next run
- Was the 148-file "stall" really capacity-driven, or purely the idle
  timeout from the user-pause? (Run 2 would test this.)

---

## Run: 2026-04-20 — genomics-product GP-1167 (second dogfood, skill-driven)

**Scope:** `components/web/**` · 150 files (R1) → 164 files (R2, post-fix)
· rounds: R1 + Fix Phase + R2
**Agents dispatched:** standards×3, regression×3, process×1 (7 total);
structured skipped as redundant
**Chunked:** yes — W1 routes+contracts (33), W2 fine-tuning (59), W3 other
features+shared components (58). Chunked because skill rule at the time
said "≤50 files/agent, split by directory." Rule has since been relaxed
(see "changes" below) — the same diff under the new rule would likely
run unchunked with 3 agents.
**Verdict:** 7 BLOCKING, 13 SHOULD-FIX, 4 WATCH, 2 NIT · 124 raw → 26 kept
(78.6% drop). Dropped breakdown: 44 category_cap, 20 not_actionable, 18
not_accurate, 15 verification_failed.
**Wall clock:** R1 ~8 min (dispatch to last agent completion), judge
13m46s, total ~22 min · **Budget:** unmeasured (gap #3) — judge alone
consumed 98.6k tokens ≈ ~$0.30 Sonnet; 7 R1 agents likely pushed total
above the $1.50 cap.
**Fix-phase outcome:**
- **BLOCKING tier (7/7): validated as real bugs.** Red-green TDD was
  applied to every UI-crash BLOCKING — tests failed pre-fix, passed
  post-fix. Of the 4 HC-promoted BLOCKINGs, all 4 real; of the 3 non-HC
  BLOCKINGs, all 3 real.
- **SHOULD-FIX / WATCH / NIT tiers (19/19): code changes applied, not
  independently bug-validated.** Fix agents were told "tackle all of
  them" so every kept finding got a change. Some of those changes were
  cosmetic (`consts/routes.ts` newline revert was a NIT — applying the
  change does not prove a bug existed). These tiers weren't covered by
  red-green TDD, so "precision" for them is an unknown — the runs log
  records only that the changes landed cleanly, not that each finding
  was a genuine bug.
- **Drop tier (97 findings): NOT validated.** Fix phase never looked at
  dropped findings; no evidence about whether the judge's filter killed
  real bugs. Would require a separate sampled pass over the drops to
  calibrate judge recall.
- **Verification (whole-app):** typecheck clean, lint 0 errors (57
  pre-existing warnings), 735 tests passed / 2 skipped / 0 failed, 10
  new test files / ~25 new tests covering the fixed UI crashes.

**Fix-phase caveat — under-scoping in 3 findings:** reviewers flagged
a symptom but named fewer files than the pattern occupied, or pointed
at the wrong caller. Real bugs in all cases, but fix-phase had to
expand scope:
- `useAction(... as any)` — flagged in some files of a pattern that
  actually spanned runs-details, manage-api-keys (delete + create),
  and cookbook forms.
- `stageModelAction` typed `any` — root cause in
  `lib/utils/safe-action.ts` was missed; only callsites were flagged.
- `editCookbookGuide(id)` → `editCookbookGuide({slug, newSlug})` —
  the named caller was not the only one; `edit-guide-form.tsx` also
  needed updating.

**R2 phase (adversarial, post-fix):** Agents 5×E (adversarial,
metadata-blind) chunked W1/W2/W3, 164 files. 64 raw findings → 24
surviving after verify+filter+dedupe: 7 BLOCKING, 11 SHOULD-FIX,
6 WATCH. Judge: ~5m 10s, 69.8k tokens (smaller input than R1 judge
→ faster). R2 still used `/tmp/*.json` disk handoff for findings
despite the new inline-handoff rule — either stale skill state or
rule not followed; confirm on next run.

**R2 BLOCKINGs broke into three categories:**
- **Fix-induced regressions (3):** B1 lint bug (imports after type
  declarations) introduced by Cluster C; B6 sentinel half-done
  (write-path fixed, read-path not — `?order-form=ALL` deep-link
  leaks 'ALL' literal into backend); B7 `orderFormId=null/undefined`
  literal in fetch URL. None caught by per-cluster typecheck/lint/tests
  because they were semantic, not syntactic, and crossed cluster
  boundaries.
- **Fix-incomplete findings (1):** B2 stageModelAction — Cluster B's
  fix was "directionally correct but incomplete." Inner try/catch
  still swallows errors into `result.data.failure`; serverError never
  fires. Same under-scoping pattern as R1 findings — fix-phase output
  can be under-scoped too.
- **R1 blindspots (3):** B4 useTestSetUpload `useAction(createTestFiles
  as any)` structurally broken; B5 fetchPaginatedBalanceHistory
  camelCase outlier; several SHOULD-FIX (delete-run-modal silent
  success, `RUN_STATUS.Created=0` truthy-drop in SignalR handler,
  duplicate vi.mock factories). These were in R1's scope but R1 didn't
  surface them — single-pass review has real recall gaps.

**R2 verdict:** "Needs Work" — reviewer's own honest assessment from
the session transcript: "R2 was clearly worth running. It caught real
fix-induced regressions in my own work that no single-pass review
would have found."

### What worked
- High-confidence promotion logic earned its keep: 4 of 7 BLOCKINGs were
  flagged by ≥2 independent reviewer lenses (standards + regression
  converging on fileSize type flip, release-candidate-actions unguarded
  optional chains, GET_RUNS endpoint rename breaking use-get-logs,
  useAction() `as any` patterns). Post-fix: all 4 HC BLOCKINGs were
  real bugs. HC precision in this run: 4/4. (Non-HC BLOCKINGs also 3/3 —
  small sample can't yet prove HC is MORE predictive than non-HC;
  need Gap #6 data across ≥3 runs.)
- Kept findings were all actionable: fix phase applied code changes to
  all 26 without any reviewer-complaint of "this finding doesn't
  reproduce / can't be fixed." (This says nothing about the 97 dropped
  findings — those are uncalibrated; would need a sampled pass over
  drops to validate judge recall.)
- Parallel fix clusters (4 dev agents with non-overlapping file scopes)
  completed in ~4 min wall-clock. Each cluster ran its own typecheck +
  lint + tests before returning, then a whole-app sweep confirmed
  integration. Red-green TDD applied to every UI-crash finding. This
  pattern deserves its own §Fix Phase writeup in the playbook
  (currently underspecified).
- **R2 decisively earned its cost.** 7 BLOCKINGs, of which 3 were
  fix-induced regressions that would have shipped without R2, 3 were
  R1 blindspots on unfixed code, and 1 was a fix-incomplete finding.
  The playbook already recommends R2 on follow-up reviews; this run
  is strong evidence the recommendation should become automatic
  rather than optional (Gap #5). R2's own judge was faster than R1's
  (5m vs 13m) because the pre-filtered input was smaller.
- Judge's 78% drop rate is working as intended — separates real findings
  from reviewer noise. Dropped breakdown (44 category_cap, 18 not_accurate,
  15 verification_failed) matches expected shape.
- Markdown-first rendering was readable and scannable; user could act on
  it without touching the JSON envelope.
- User's one-sentence scope override ("only components/web files") applied
  cleanly — skill re-chunked with no friction.

### What didn't
- Pre-flight built a full 10-agent/3-component plan before asking scope.
  User had to correct. Cost ~2 min of crunching + 2 tool calls of wasted
  chunking before re-scoping.
- R1→judge handoff used `/tmp/review_r1_findings.json` file. Write tool
  display output showed garbled content (lines merged mid-string:
  `"files_changed": 150,nents/web/**"`). Unverified whether on-disk bytes
  were actually corrupt or only the terminal rendering. Either way, the
  disk round-trip erased visibility into what the judge saw.
- Chunking tripled the R1 agent count (3 → 7) without clear evidence of
  value. Playbook's "≤50 files/agent" rule was thinly justified (from
  Run 1's misdiagnosed stall).
- No budget accounting in the envelope. Cap was stated (`$1.50`) but not
  enforced or reported post-run.
- Process agent (3 WATCH-level only, nothing actionable) felt like dead
  weight on a well-formed PR. No BLOCKING/SHOULD-FIX contribution.
- Branch already had a prior multi-agent review commit (bab08177d "address
  multi-agent PR review findings") — indicating this was a follow-up review.
  Skill did not detect or flag this; 7 new BLOCKINGs after a prior pass
  suggests the fixes themselves introduced regressions, which would have
  justified an automatic R2 recommendation.
- **Fix Phase per-cluster verification is insufficient.** Each cluster
  ran typecheck + lint + tests and came back green, yet R2 found a
  CI-breaking lint bug (imports interleaved with types), a half-done
  sentinel fix (write-path fixed, read-path not), and a dead
  abstraction (ServerOnlyApiError with zero importers). Per-cluster
  checks catch syntactic errors but not semantic regressions or
  cross-cluster interactions. Fix Phase needs an adversarial review
  step before declaring done (see Gap #8).
- **Fix-phase output can be under-scoped.** Cluster B's stage-model
  fix was "directionally correct but incomplete" — the inner try/catch
  still swallowed errors. Same under-scoping pattern the R1 reviewers
  had. Whatever mitigation applies to reviewer under-scoping (Gap #7)
  should apply to fix agents too.
- **R1 has non-trivial recall gaps.** R2 found ~10 correctness bugs
  that were present in R1's scope (delete-run-modal silent-success,
  `RUN_STATUS.Created=0` truthy-drop, duplicate vi.mock factories,
  TZ-dependent expiry helper). R1's 124 raw findings were not
  exhaustive. "R1 + judge" is not a safe default on production-critical
  or follow-up review PRs.

### Playbook/skill changes this run produced
- **Playbook §Chunking:** relaxed from "≤50 files/agent, chunk by default"
  to "no chunking up to ~200 files; chunk only on evidence (prior stall,
  >200 per agent, or user request)". Rationale: Run 2 proved 150-file
  scopes complete fine; the `150 → 50×3` split multiplied cost for no
  measurable quality gain.
- **Playbook §Judge Phase → Handoff format:** require inline findings
  (JSON or NDJSON embedded in the judge prompt); forbid `/tmp/*.json`
  round-trip.
- **Skill Step 1a:** new multi-component scope ask — detect 2+ top-level
  component prefixes, ask user to narrow BEFORE building the checklist.
- **Skill Step 1b chunks row:** updated to match relaxed playbook default.
- **Skill Step 3:** added explicit "inline, not file" directive pointing
  to the new playbook rule.

### Open questions for next run
- Validate the relaxed chunking rule: run a ~150-file diff unchunked
  (3 agents, one per lens), compare wall-clock + finding quality vs
  Run 2's chunked numbers. Did anything get missed by the single-pass
  standards agent vs the 3 chunked ones?
- **Under-scoping mitigation.** Three Run 2 findings flagged a symptom
  but missed the full pattern. Worth testing: does giving reviewers an
  explicit "if you flag a pattern, grep for all instances before
  reporting" instruction reduce under-scoping, or does it bloat
  findings with false matches?
- HC vs non-HC precision — Run 2 hit 100% on both (7/7 BLOCKINGs real).
  Need ≥2 more runs with ≥1 false-positive BLOCKING to calibrate
  whether HC is more predictive than non-HC, or just a dedup tag.
- Should the skill detect prior-review-commits on the branch and
  auto-recommend R2?
- Process agent default: keep as part of the roster, or demote to
  opt-in?
- §Fix Phase writeup — the playbook currently has a terse Fix Phase
  section. Run 2's fix-phase pattern (4 parallel clusters with
  non-overlapping file scopes, red-green TDD per finding, per-cluster
  verify + whole-app final sweep, explicit "out-of-cluster scope"
  flagging for under-scoped findings) is worth documenting as the
  default shape.

### Pending (not yet validated against a fresh run)

Rewritten 2026-04-20 after the playbook+skill v2 rewrite. Items below
are either open or "closed-in-theory, pending next run's evidence."

**Closed by v2 rewrite — pending validation in next run:**
- **Gap #3 (budget accounting).** Envelope now carries
  `budget_spent_usd` per phase. Needs a run that actually populates it.
- **Gap #4 (process agent).** Process lens removed; its one
  high-value function (run tests) is now the `tests` agent in R1.
- **Gap #5 (follow-up-review detection).** Superseded: R2 now runs
  by default after every Fix Phase, regardless of prior-review-commit
  status. Skill Step 1b detects post-fix branches via `git log --grep`
  and swaps agent roster accordingly.
- **Gap #7 (under-scoping).** §Mandatory rules and §Fix Phase both
  include "grep for all instances in path_filter before reporting /
  fixing." Needs a run that tests whether this bloats findings with
  false matches.
- **Gap #8 (Fix Phase under-specified).** §Fix Phase now fully spec'd:
  parallel clusters with disjoint scope, TDD for every BLOCKING with a
  reproducible failure mode (not just UI crashes — Run 2 evidence),
  per-cluster + whole-app checks, under-scoping rule, third-party
  research-before-fix, and mandatory R2 handoff.
- **Gap #9 (inline judge-handoff rule).** Still only stated once in
  the playbook (§Judge → Input) and skill (§Step 3). Needs a run that
  confirms the rule is actually followed. No stronger mitigation yet;
  if it's ignored again, escalate to a pre-dispatch check.

**Open — requires more run data:**
- **Gap #6 (HC precision).** Still a one-run sample. Need ≥2 more
  runs with at least one false-positive BLOCKING to calibrate whether
  `high_confidence` is more predictive than non-HC, or just a dedup tag.

**Reopened by Run 3:**
- **Gap #5 (follow-up-review detection).** v2 claimed this was
  superseded ("R2 runs by default after every Fix Phase"). Run 3
  exposed a gap in the fall-through logic: commit-grep match without
  an R1 envelope should default to R1, not R2. Detection itself is
  fine; the default picked from the detection was wrong. Fixed in
  Skill Step 1b via Run 3's edit (three-way branch: match+envelope →
  R2; match+no-envelope → R1; no-match → R1). Needs a run where the
  user actually hands over an R1 envelope to confirm the R2 branch
  still fires cleanly.

---

## Run: 2026-04-22 — genomics-product GP-1167 (third dogfood, post-v2 skill)

**Scope:** `components/web/**` · 266 files · pipeline: R1 only
(Fix Phase + R2 pending user)
**Pass type:** R1 (fresh) — but Step 1b initially picked R2 on
`git log --grep` match of two prior review-fix commits (bab08177d,
b6eabee49). Safeguard blocked on missing R1 envelope; user overrode
manually ("do r1 and then r2. is the skill not clear on that?").
**Agents dispatched:** R1: aligned×1, adversarial×1, tests×1 (default
roster)
**Chunked:** no — 266 files in a single cohesive component, no prior
stall on this diff, user did not override
**Verdict:** 3 BLOCKING, 7 SHOULD-FIX, 5 WATCH, 4 NIT · 26 raw
(aligned 13 + adversarial 13 + tests 0) → 19 kept + 3 dropped (HC
dedup collapsed the balance)
**Wall clock:** R1 ~2 min (dispatch to last-agent complete), judge
2m47s, total ~5 min
**Budget:** `budget_spent_usd` fields returned null — Gap #3 still
open (no wiring)
**Fix-phase outcome:** pending — user has not run Fix Phase yet

### What worked
- R1 roster dispatched cleanly within the 5-min cache window; all
  three agents returned within ~2 min.
- 3 BLOCKINGs are all real regressions from one upstream change
  (api-client now throws on non-OK response): use-get-logs endpoint
  swap → 404, upload-form validation-message swallowing, cookbook
  edit-guide page crash. Adversarial lens caught all three; aligned
  missed them because the refactor itself was intent-consistent —
  bugs live in the blast radius of a "reasonable" change, which is
  exactly where adversarial lens earns its keep.
- HC promotion still working: `RUN_STATUS.Created = 0` truthy-drop in
  SignalR handler flagged by aligned + adversarial independently.
  Pre-existing, preserved through the cache-updater extraction.
- Markdown summary was scannable at a glance: severity groups,
  `file:line`, one-sentence message, HC tag.
- Tests agent was a ~30s no-op (suite passing on the branch) and
  completed first — the roster isn't expensive when empty.

### What didn't
- **Pass-type detection over-committed to R2 without R1 findings.**
  Step 1b matched two prior review-fix commits → picked R2 roster →
  then blocked asking for R1 envelope. The block was a correct
  safeguard, but the pick itself was wrong: without R1 findings in
  hand, fix_verifier has nothing to verify (degrades to a second
  adversarial agent, which is worse than a clean R1 roster). User
  had to manually override — exactly the friction the pre-flight
  was supposed to eliminate.
- **JSON envelope dumped to user-facing output.** Step 4 said
  "markdown first, JSON second in a fenced code block for Fix Phase
  agents and future automation." In practice: ~300 lines of JSON
  duplicating every finding after a clean 20-line markdown table.
  User cannot act on the JSON; Fix Phase dev agents get the envelope
  via in-session prompt context, not the chat transcript. The
  argument "for future automation" didn't survive contact with a
  user who just wants the table.
- Budget still unmeasured. `budget_spent_usd` null in the envelope.
  Gap #3 needs actual wiring — Agent tool responses carry token
  counts, nothing aggregates them.

### Playbook/skill changes this run produced
- **Skill Step 1b:** flip default. `match + R1 envelope provided by
  the user → R2`. `match + no envelope → R1 (default, no block)`.
  No blocking question; the user can always request R2 explicitly
  and accept the fix_verifier degradation.
- **Skill Step 4 + What NOT to do:** JSON envelope is internal state.
  NOT rendered to the chat. Not persisted to disk (user explicitly
  rejected `.reviews/` and `/tmp/*.json` persistence). Markdown is
  the ship format; R2 re-invocations rely on user paste-back.
- **Playbook §Judge step 6 + §Markdown summary:** aligned with the
  skill. Envelope spec stays (internal contract for Fix Phase dev
  agents); rendering is markdown-only.

### Open questions for next run
- **Gap #3 (budget accounting).** Still null. Wire it, or acknowledge
  the field is aspirational and remove it from the envelope spec.
- **R2 hand-off after the JSON-output fix.** Run 3 didn't reach Fix
  Phase or R2. Next run that does needs to confirm Fix Phase dev
  agents still receive the envelope via prompt context (no chat
  render, no disk cache) and that a subsequent R2 invocation with
  user-pasted R1 markdown fires the fix_verifier branch cleanly.
- **Gap #6 (HC precision).** Run 3 had 1 HC finding (SignalR status=0
  truthy-drop). Not enough to calibrate. Still open.
- **Why the adversarial lens out-performed aligned 3-to-0 on
  BLOCKINGs.** The refactor was intent-consistent; aligned read the
  intent and didn't look hard at blast radius. Worth testing whether
  an aligned-plus-adversarial prompt tweak (explicit "audit the
  blast radius of intent-consistent refactors") closes the gap.
