# PR Review Golden Set

Curated fixtures with known bugs for regression-testing the multi-agent
PR review pipeline (`../multi-agent-pr-review.md` playbook +
`../../claude/skills/review-multi-agent/SKILL.md` invocation wrapper).

**Why.** Without this, every playbook change is validated by "reading
the runs log and hoping." The golden set gives each change a concrete
"did it still catch this bug?" check. It complements the runs log —
the runs log records what happened in the wild; the golden set tests
what should happen on controlled inputs.

**What this does NOT do (yet).**
- Does NOT auto-invoke the pipeline. Invocation is manual via
  `/review-multi-agent` after `./run.sh <fixture>` sets up the
  throwaway repo.
- Does NOT assert exact message wording. Pipeline output is stochastic —
  match by severity + file + keyword, never exact string.
- Does NOT measure recall across a PR corpus. Each fixture is a single
  bug targeted at a single failure mode.

Scaling beyond MVP (add fixtures, add an eval script) is future work;
start here.

## Quick start

```bash
./run.sh 01-case-sensitive-search
# prints the throwaway-repo path and instructions; cd into it, invoke
# /review-multi-agent, compare actual findings to expected.json
```

`run.sh` sets up a fresh git repo in `$TMPDIR` with two commits: the
baseline (`before.*` files) and the PR diff applied on top. You then
point the skill at it.

## Schema (`expected.json`)

```json
{
  "description": "one-liner: what bug this fixture introduces",
  "minimum_findings": [
    {
      "severity": "BLOCKING | SHOULD-FIX | WATCH | NIT",
      "category": "correctness | regression | security | perf | ...",
      "file_regex": "pattern matching the relevant file path",
      "line_regex": "pattern matching the buggy line(s)",
      "message_keywords": ["at least one", "must appear", "in the finding's message"],
      "notes": "human explanation of what the pipeline should flag and why"
    }
  ],
  "acceptable_false_positives": 1,
  "notes": "what failure mode this fixture targets; link to runs-log entry if derived from a real run"
}
```

**Pass criteria:** every `minimum_findings` entry is matched by at
least one finding in the pipeline's output. A finding matches if:
- `severity` is at least as severe (BLOCKING ≥ SHOULD-FIX ≥ WATCH ≥ NIT)
- finding's `file` matches `file_regex`
- at least one `message_keywords` entry appears in the finding's
  `message` (case-insensitive)

Actual findings beyond the minimum are OK up to
`acceptable_false_positives`. Findings over that threshold indicate
pipeline noise — log in the runs log's "What didn't work" section.

## Adding a fixture

1. Create `fixtures/NN-short-name/`
2. Add a `setup/` subdirectory containing the pre-PR state. Everything
   under `setup/` is copied into the throwaway repo verbatim (preserving
   structure). Put files at their intended paths — e.g. `setup/src/utils.ts`
   lands as `src/utils.ts` in the work dir.
3. Add `diff.patch` — unified diff generated via `git diff >
   diff.patch` from a test repo where the before-state matches `setup/`
   and the after-state contains the bug. The patch must apply cleanly
   against `setup/`'s layout.
4. Add `expected.json` using the schema above.
5. Add a row to the table below.

**Fixtures should target known failure modes.** Don't add generic
bugs; pick ones the runs log has either flagged as caught or missed,
or ones that exercise a playbook rule you want to stress-test.

## Current fixtures

| # | Name | Targets | Derived from |
|---|---|---|---|
| 01 | case-sensitive-search | Regression: case-sensitive string comparison on a search path | Run 1 BLOCKING: `app/api/fine-tuning/runs/route.ts:19` |

## Future fixture ideas (not yet built)

- `02-under-scoping` — a pattern that appears in 4 files, diff
  introduces bug in 2 of them; expected: pipeline flags all 4 or
  explicitly notes the pattern needs wider grep (tests the
  under-scoping rule)
- `03-third-party-dead-code` — a claim that a third-party SDK function
  is unused, where reading the installed code would show it IS used;
  expected: pipeline does NOT promote the dead-code claim to BLOCKING
  without verification via reading installed code (tests the
  grep-is-not-proof rule)
- `04-fix-induced-regression` — a branch with a "address review
  findings" commit where the fix itself introduced a new bug;
  expected: R2 detection via `git log --grep`, fix_verifier or
  adversarial catches the new bug (tests R2 auto-dispatch + fix-phase
  regression defense)
- `05-sycophancy` — same as 04 but with a particularly strong-looking
  "I have carefully verified this fix is complete" commit message;
  expected: fix_verifier withholds the commit subject and still
  flags the issue (tests commit-subjects-withheld rule)
