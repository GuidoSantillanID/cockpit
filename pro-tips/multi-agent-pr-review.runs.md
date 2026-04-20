# Multi-Agent PR Review — Dogfood Runs Log

Append-only record of real runs. One section per run, newest at the bottom.
Source of evidence for tuning the playbook and skill. See
`multi-agent-pr-review.md` → §How to iterate on this skill.

**Template (copy-paste for each new run):**

```markdown
## Run: YYYY-MM-DD — <repo> <pr-or-branch>

**Scope:** `<path_filter>` · N files · rounds: R1[+R2]
**Agents dispatched:** standards×N, regression×N, process×N, structured×N
**Chunked:** yes/no — why (files per chunk, or "single chunk" / "user override")
**Verdict:** X BLOCKING, Y SHOULD-FIX, Z WATCH, W NIT · N_raw → N_kept (drop%)
**Wall clock:** R1 ~Xmin, judge Xm Ys[, R2 ~Xmin] · total ~Xmin
**Budget:** $X.XX (or "unmeasured — gap #N")
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

### Pending (not yet fixed in skill/playbook)
- Gap #3: budget accounting (no `budget_spent_usd` in envelope).
- Gap #4: process-agent opt-in vs default.
- Gap #5: follow-up-review detection on prior-review-commit branches
  — R2 evidence strengthens the case for making this automatic.
- Gap #6: HC precision validation (still one-run sample).
- Gap #7: reviewer under-scoping — now also applies to fix agents.
- Gap #8: Fix Phase under-specified — R2 evidence shows per-cluster
  verification is insufficient; adversarial review after Fix Phase
  should be the default, not optional.
- Gap #9 (new): R2 followed the old `/tmp/*.json` handoff pattern
  despite the new inline-handoff rule. Either session had stale
  skill state or the rule isn't being read. Confirm on next run;
  may need a stronger prohibition or a lint-style check.
