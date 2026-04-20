# Multi-Agent Code Review: Reference Guide

> Research compiled from official docs, blog posts, academic papers, community discussions, and installed tooling. **Last refreshed: April 17, 2026. External-sources fact-check pass: April 18, 2026.**
>
> Signal quality note: vendor self-reports (e.g. "<1% false positive rate") diverge sharply from independent academic benchmarks (15–31% detection, sub-20% F1). Treat unvetted vendor numbers with suspicion.

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [1. Architecture Patterns](#1-architecture-patterns)
- [2. Judge / Verifier Pattern (Deep Dive)](#2-judge--verifier-pattern-deep-dive)
- [3. Failure Modes & Anti-Patterns](#3-failure-modes--anti-patterns)
- [4. Battle-Tested Performance Data](#4-battle-tested-performance-data)
- [5. Cost Optimization Playbook](#5-cost-optimization-playbook)
- [6. Best Practices for Review Agent Context](#6-best-practices-for-review-agent-context)
- [7. Single vs Multi-Agent: When It Matters](#7-single-vs-multi-agent-when-it-matters)
- [8. External Tools and Frameworks (April 2026)](#8-external-tools-and-frameworks-april-2026)
- [9. Claude Code Subagent Configuration](#9-claude-code-subagent-configuration)
- [10. Installed Superpowers Skills](#10-installed-superpowers-skills)
- [11. Installable Skills from skills.sh](#11-installable-skills-from-skillssh)
- [12. Implementation Recipes](#12-implementation-recipes)
- [13. What Humans Should Still Review](#13-what-humans-should-still-review)
- [14. Recommendations](#14-recommendations)
- [15. Sources](#15-sources)

---

## Executive Summary

Six facts that matter more than everything else below.

1. **The judge pattern is the signal lever — but it has documented biases.** HubSpot's 3-criteria judge drove their approval rate to 80%+ and TTFF down 90% ([product.hubspot.com](https://product.hubspot.com/blog/automated-code-review-the-6-month-evolution)). But judges inherit generator biases, prefer verbose output, favor security-framed findings, and show systematic robustness gaps on their own outputs ([arXiv 2506.09443](https://arxiv.org/abs/2506.09443): up to 40% variance across prompt templates; [arXiv 2505.16222](https://arxiv.org/abs/2505.16222) documents 6 bias types). **Use a different provider/model for the judge than the reviewers if possible.** Strip PR titles and commit messages before judging — framing effects drop vulnerability detection 16–93% ([arXiv 2603.18740](https://arxiv.org/abs/2603.18740)).

2. **Sonnet-as-judge beats Opus-as-judge once input is pre-filtered.** Sonnet 4.6 (79.6% SWE-bench) vs Opus 4.6 (80.8%) — a 1.2-point gap at ~60% of Opus per-token cost (Sonnet $3/$15 vs Opus $5/$25; both ratios are 0.6). Anthropic's own advisor pattern (Opus plan + Sonnet execute) cuts total cost ~11% vs all-Opus with quality gains ([MindStudio](https://www.mindstudio.ai/blog/claude-code-advisor-strategy-opus-sonnet-haiku)). Anthropic's built-in Code Review dispatches parallel AI agents per PR ([claude.com/blog/code-review](https://claude.com/blog/code-review)); the specific Haiku-vs-Sonnet split is not publicly documented in precise terms.

3. **Prompt caching is the single biggest cost lever (up to 90% input cost reduction).** Structure every review call as `[shared system + patterns + diff][cache_control breakpoint][per-reviewer lens]`. Fire all N reviewers within 5 minutes of cache warm-up. Cache reads are 10% of base input cost; writes are 125% (5-min TTL) or 200% (1-hour) — single-shot use is net-negative.

4. **Multi-agent review has documented catastrophic failure modes.** A $47,000 invoice came from two agents exchanging messages for 11 days while everyone assumed they were working ([earezki.com case study](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/)). CVE-2025-53773 was a Copilot RCE via prompt-injected comments flipping settings to YOLO mode ([embracethered.com](https://embracethered.com/blog/posts/2025/github-copilot-remote-code-execution-via-prompt-injection/)). Hard per-run token budgets and circuit breakers are not optional.

5. **Vendor numbers disagree with independent benchmarks by an order of magnitude.** Anthropic reports <1% false positive rate internally; Martian Code Review Bench (17 tools, 200k+ PRs, March 2026) measured CodeRabbit at 49.2% precision / 51.2% F1 ([codereview.withmartian.com](https://codereview.withmartian.com/)); Qodo self-reports 60.1% F1 on their own benchmark; SWE-PRBench across 8 frontier models shows 15–31% detection, 19–42% hallucination. Don't take vendor marketing as a planning input.

6. **Grep is not proof of absence.** Symlinks, pnpm content-addressed store, compiled/transpiled output, TS path aliases, dynamic imports, reflection, and interface dispatch all hide code from grep. Require adversarial agents to READ the actual installed file at the expected path. Cross-verify any "X doesn't exist" claim with a second tool (call-graph analysis, AST walk).

---

## 1. Architecture Patterns

### Anthropic Code Review (Claude Code, March 2026)

Shipped March 9, 2026 ([TechCrunch](https://techcrunch.com/2026/03/09/anthropic-launches-code-review-tool-to-check-flood-of-ai-generated-code/), [claude.com/blog/code-review](https://claude.com/blog/code-review)).

- **Multi-agent team** dispatches in parallel, each agent scoped to a single issue class: logic errors, boundary conditions, API misuse, auth flaws, convention violations.
- **Verification layer** filters false positives before posting — <1% of findings dismissed as incorrect per Anthropic's internal measurement. External benchmarks do not confirm this number.
- **Scaling behavior**: larger PRs get more agents dispatched. 84% of PRs over 1,000 lines now get findings. Average 7.5 issues on 1,000+ LOC PRs.
- **Before/after**: 16% → 54% of PRs receive substantive review comments.
- **Cost**: $15–25 per review on token usage, Team/Enterprise plans only.
- **Output**: one high-signal overview comment + inline annotations ranked by severity.
- **Wall-clock**: ~20 min average per review (published; no median/p95 by PR size).

### The Core Multi-Agent Shape

```
User Completes Work
    │
    ▼
[Verification Pre-flight] ── run tests, exit codes, evidence before claims
    │
    ▼
[Dispatch Reviewers] ── parallel subagents, focused single-lens scope
    │
    ├── Spec / Correctness
    ├── Regression (runs tests)
    ├── Security Reviewer (conditional)
    ├── Adversarial Reviewer
    └── Performance / Simplification
    │
    ▼
[Judge / Synthesizer] ── filter by succinctness / accuracy / actionability
    │                    dedupe, rank, apply bias mitigations
    ▼
[Categorized Output] ── BLOCKING > SHOULD-FIX > WATCH > NIT
    │
    ▼
[Handle Feedback] ── verify before implementing, push back when wrong
    │
    ▼
[Re-verify] ── fresh verification that fixes actually work
    │
    ▼
Ready to Merge
```

### HAMY 9-Agent Pattern (Feb 2026)

From [HAMY's blog](https://hamy.xyz/blog/2026-02_code-reviews-claude-subagents). Deploys 9 parallel subagents via `/code-review`. Qualitative report: ~75% useful findings (up from <50% single-agent).

| Agent | Focus |
|-------|-------|
| Test Runner | Execute tests, report pass/fail with details |
| Linter & Static Analysis | Type errors, unresolved refs, lint violations |
| Code Reviewer | Top 5 improvements ranked by impact/effort |
| Security Reviewer | Injection, auth, secrets, error handling leaks |
| Quality & Style | Complexity, dead code, duplication, conventions |
| Test Quality | Coverage ROI, behavioral vs implementation tests, flakiness |
| Performance | N+1 queries, blocking ops, memory leaks, hot paths |
| Dependency & Deploy Safety | Breaking changes, migration safety, observability |
| Simplification & Maintainability | Could code be simpler? Atomicity, change scope |

Synthesis: three-tier verdict (Ready / Needs Attention / Needs Work), findings split Issues vs Suggestions, ranked Critical > High > Medium > Low, clean results collapsed into one-liners, duplicates merged.

HAMY did not publish an agent-count ablation — 9 was chosen qualitatively.

### Anthropic Advisor Strategy (Opus plan + Sonnet/Haiku execute)

Published pattern for cost optimization ([MindStudio breakdown](https://www.mindstudio.ai/blog/claude-code-advisor-strategy-opus-sonnet-haiku)):

- Opus as planner/reviewer, Sonnet/Haiku as executor
- Benchmarked result: ~11% total session cost vs all-Opus, often with quality improvements
- Applies cleanly to the reviewer/judge split

---

## 2. Judge / Verifier Pattern (Deep Dive)

The single most impactful architectural decision in multi-agent code review.

### Why it matters

- **HubSpot Sidekick**: added the judge layer → 80%+ engineer approval, ~90% TTFF reduction (peaked 99.76% in Sept 2025) ([InfoQ](https://www.infoq.com/news/2026/03/hubspot-ai-code-review-agent/)).
- **Greptile**: added embedding-based judge filter (cosine similarity to past upvoted/downvoted comments) → addressed-comment rate moved 19% → 55%+ in two weeks ([ZenML LLMOps DB](https://www.zenml.io/llmops-database/improving-ai-code-review-bot-comment-quality-through-vector-embeddings)).
- **Anthropic Code Review**: verification layer filters <1% of findings (their measurement).
- **Caveat**: no org has published an isolated ablation of the judge layer alone. The "biggest lever" claim is narrative, not measured.

### Criteria variations in production

| System | Criteria |
|---|---|
| HubSpot Sidekick | succinctness / accuracy / actionability |
| Qodo reflect prompt | suggestion_score (0–10) + `why` (1–2 sentences) + `relevant_lines_start/end` for grounding |
| Greptile | 0–5 PR confidence + per-comment embedding similarity to historical up/downvotes |
| Anthropic Code Review | bug-likelihood + verification-against-code-behavior + severity rank |
| G-Eval (generic) | rubric + CoT steps generated by LLM itself |

### Qodo's published judge prompt (verbatim mechanics)

Only fully-published production judge prompt. From [github.com/qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent/blob/main/pr_agent/settings/code_suggestions/pr_code_suggestions_reflect_prompts.toml).

Key mechanics worth stealing:

- **Scoring 0–10.** Score=0 forces elimination.
- **Hard category caps** (deterministic ceilings on common low-value classes):
  - Error handling / type checking suggestions → max 8
  - Suggestions that only ask the user to verify → max 7
  - `existing_code` identical to `improved_code` → max 7
- **Forced zero** on: docstrings, type hints, unused imports, "use more specific exception types," questions about entities defined outside the diff.
- **Grounding clause** (anti-hallucination): "Validate the `existing_code` field by confirming it matches or is accurately derived from code lines within a `__new hunk__` section."
- **Output**: YAML conforming to a Pydantic schema. Required fields: `suggestion_score`, `why`, `relevant_lines_start`, `relevant_lines_end`.

Inspired by AlphaCodium's flow engineering.

### Documented judge biases (MUST mitigate)

From [arXiv 2505.16222 "Don't Judge Code by Its Cover"](https://arxiv.org/html/2505.16222v1):

| Bias | Magnitude |
|---|---|
| Authority bias (claims of expert authorship) | Inflates scores |
| Self-declared correctness | +5.3 to +7.8 pp (up to −24.7pp on LLaMA-3.1-70B) |
| Misleading task descriptions | GPT-4o accuracy −26.7pp; mean abs deviation 15.3pp |
| Illusory complexity (longer names, more code) | Higher scores regardless of quality |
| Structural verbosity bias | Long walkthroughs rated higher than concise summaries (inverse of human preference) |

**Scale does not cure it** — bigger models show the same patterns.

### Confirmation bias (critical for security review)

From [arXiv 2603.18740 (USENIX Security)](https://arxiv.org/html/2603.18740) on framing effects in security review:

- Framing a diff as "bug-free" drops vulnerability detection **16–93%** across models.
- GPT-4o-mini: 97.2% → 3.6% on adversarial framing.
- Claude 3.5 Haiku: 68.4% → 8.5%.
- **88% attack success rate vs Claude Code in autonomous mode** (35% vs Copilot).
- False-negative bias exceeds false-positive bias by 4–114×.

**Mitigations that worked in the study:**
- Metadata redaction alone → recovered 68.75% of missed detections.
- Metadata redaction + explicit de-biasing instructions → recovered **94%**.

Implication: do **not** feed the judge PR titles, descriptions, commit messages, or branch names if you want independent review. Reviewers can see them (they need intent); the judge should not.

### Alternative synthesizer patterns

- **Self-consistency** (N samples, majority vote) — standard.
- **Multi-agent debate with adaptive stability detection** ([arXiv 2510.12697](https://arxiv.org/html/2510.12697v1)).
- **Modular evaluation + majority voting** — used in [Agent-as-a-Judge](https://arxiv.org/html/2410.10934v2); 90% alignment with human consensus (vs LLM-as-Judge 70%); ~97.7% time and ~97.6% cost reduction vs a 3-human expert panel. (Not tournament/pairwise; the paper uses modular components + majority voting.)
- **Ranked voting (Borda / IRV / MRR)** — [arXiv 2505.10772](https://arxiv.org/html/2505.10772v1).
- **Embedding-similarity-to-historical-feedback** — Greptile (only production-deployed "learn from past votes" variant documented).

### Judge prompt-engineering patterns

1. **CoT before verdict** — improves alignment with human judgment, adds auditability.
2. **Few-shot: 1 example peaks.** More shots degrade code-eval performance.
3. **Structured output** — YAML/JSON with required `why` field forces grounding, reduces handwaving.
4. **Hard category caps** (Qodo pattern) — deterministic ceilings on low-value categories beats "ask judge to be strict."
5. **Low temperature (0.2–0.3)** for calibration stability ([Monte Carlo](https://www.montecarlodata.com/blog-llm-as-judge/)).
6. **Metadata redaction** — strip narrative before judging.
7. **Cross-provider judge** — use a different model family than the reviewers to break same-model bias.

### Judge model choice

- Anthropic advisor strategy (Opus plan + Sonnet/Haiku execute): −11% cost, +2% benchmark vs single-Opus.
- Sonnet 4.6 (79.6% SWE-bench) vs Opus 4.6 (80.8%) — 1.2-point gap at ~60% of Opus per-token cost (further reduced by prompt caching).
- Anthropic's own Code Review dispatches **parallel AI agents with a verification layer**; the exact model mix (Haiku vs Sonnet) is not publicly specified.
- **Default: Sonnet-as-judge once reviewer input is pre-filtered.** Opus only if the judge must do heavy reasoning over unfiltered raw output.

### Tool-based verification (CodeRabbit pattern)

CodeRabbit does not publish its judge prompt. Instead it uses **tool-based verification**: generates shell/ast-grep/python checks that prove an assumption before posting. "Comments come with receipts." ([coderabbit.ai](https://www.coderabbit.ai/blog/how-coderabbit-delivers-accurate-ai-code-reviews-on-massive-codebases)).

Adoptable pattern: require every adversarial-agent claim to include a shell command that proves it. The judge runs the command; if it fails, the finding is dropped.

---

## 3. Failure Modes & Anti-Patterns

What breaks multi-agent review in practice. Design against these.

### 1. Hallucinated findings

**Mechanism.** Models fabricate function calls, CVEs, imports, or package references under uncertainty.

**Evidence.**
- ~20% of AI-generated package recommendations point to libraries that don't exist.
- 29–45% of AI-generated code contains security issues the agent then misattributes ([diffray.ai](https://diffray.ai/blog/llm-hallucinations-code-review/)).
- AST-based post-hoc verification catches them at 100% precision, zero false positives in lab conditions ([arXiv 2601.19106](https://arxiv.org/html/2601.19106v1)).

**Mitigation.** Deterministic AST verification achieves 77% auto-fix. RAG + RLHF + guardrails combo reached 96% reduction in Stanford study. No single tool eliminates them.

### 2. Grep-is-not-proof (the dead-code trap)

**Mechanism.** Agents use grep/ripgrep as evidence of absence. Misses: symlinks, pnpm content-addressed store, compiled/transpiled output, TS path aliases, dynamic imports, reflection, interface dispatch.

**Evidence.** Go `deadcode` docs explicitly warn of false positives via interfaces and reflection. The [codestudy.net guide](https://www.codestudy.net/blog/find-dead-code-in-golang-monorepo/) recommends combining callgraph + grep + manual validation because grep alone lies. Our own paired playbook has a documented incident: a research agent claimed a third-party SDK function was "dead code — never imported"; three round-2 agents confirmed it was alive and used by 5 internal modules.

**Mitigation.** Route Grep/Glob calls through AST/call-graph-aware interceptors (e.g. [repowise](https://github.com/repowise-dev/repowise) enriches every grep with top-3 semantic matches). Require cross-verification by ≥2 independent tools before acting on any "not found" claim. Always READ the actual installed file at the expected path.

### 3. Over-classification / severity inflation

**Mechanism.** Uniform severity grading; refactors and typos get the same BLOCKING label.

**Evidence.** CodeAnt reports 200–400 AI comments/week, 70–90% ignored ([codeant.ai](https://www.codeant.ai/blogs/prevent-ai-code-review-overload)). LLM-as-judge robustness is brittle across prompt templates and category ordering — 11 bias types documented across pointwise-scoring judges ([arXiv 2510.12462](https://arxiv.org/html/2510.12462v1)).

**Mitigation.** Risk-based routing (auth/API = deep review; docs = fast-track). Policy files encoding severity thresholds. Hard caps on specific categories (Qodo pattern).

### 4. Review fatigue / noise

**Mechanism.** Comment volume exceeds human tolerance; engineers rubber-stamp or ignore.

**Evidence.** Jet Xu framework: signal ratio **<60% = noise generator, >80% = great** ([jetxu-llm](https://jetxu-llm.github.io/posts/low-noise-code-review/)). Study of 22,000+ AI comments: "concise, focused comments were far more likely to lead to actual code changes." HubSpot Sidekick's judge filters to **zero comments** when nothing passes the 3 criteria — and this correlates with their 80%+ approval.

**Mitigation.** Judge-agent gate. Zero comments is a valid (often optimal) output. Treat signal ratio as an SLO. Don't reward agents for finding issues.

### 5. Prompt injection via diffs (CRITICAL)

**Mechanism.** Injection hidden in reviewed code, comments, rule files, or invisible unicode hijacks the reviewer.

**Evidence.**
- **CVE-2025-53773** — GitHub Copilot RCE via injected comments flipping `.vscode/settings.json` to YOLO mode ([embracethered.com](https://embracethered.com/blog/posts/2025/github-copilot-remote-code-execution-via-prompt-injection/)).
- [arXiv 2509.22040](https://arxiv.org/html/2509.22040v1) found ≥40% attack-success rates across coding editors.
- Datadog 2025 caught "Hackerbot" injecting via PRs in OSS repos ([datadoghq.com](https://www.datadoghq.com/blog/engineering/stopping-hackerbot-claw-with-bewaire/)).
- OWASP LLM Top 10 (2025) ranks prompt injection #1. Separately, 73% of LLM deployments have at least one critical vulnerability, but only 12% of organisations test for them (OWASP / Gartner 2025 data, cited widely).

**Mitigation.** Treat diff content as untrusted data, not instructions. Strip unicode control characters. Never auto-approve (Microsoft patched CVE-2025-53773 in Aug 2025 by disabling auto-approve by default). Disable autonomous mode for untrusted code. Clearly separate instruction context from data context.

### 6. Context saturation / large-diff degradation

**Mechanism.** "Context rot" — model quality degrades as input grows. All 18 models tested degrade; coherent text worsens recency bias ([morphllm.com](https://www.morphllm.com/context-rot)). Coding agents routinely push 100K+ tokens with high distractor density.

**Mitigation.** Chunking by file/module. AST-compressed diffs. Importance ranking before feeding reviewers. Scope each agent's context to its lens (security agent sees only auth-touching subset).

### 7. Misaligned incentives / confirmation bias

See §2 "Confirmation bias" above — framing effects drop detection 16–93%. This is in part a failure mode, not just a judge bias. The same mechanism afflicts single-agent reviewers.

**Mitigation.** Metadata redaction + explicit de-biasing instructions recovered 94% of missed detections in the study. Apply both upstream (scrub reviewer prompts) and at the judge (strip narrative).

### 8. Judge over/under-filtering

**Mechanism.** Judges inherit biases of their generator. Reduced self-correction on their own generations is documented ([CIP blog](https://blog.cip.org/p/llm-judges-are-unreliable)); [arXiv 2506.09443](https://arxiv.org/abs/2506.09443) "LLMs Cannot Reliably Judge (Yet?)" documents systematic robustness gaps — up to **40%** variance across prompt templates — and vulnerability to attacks like PAIR. Verbose/security-framed output is preferred regardless of quality.

**Mitigation.** Use a **different provider or model family** for judge than reviewers. Rotate framings. Calibrate against a labeled gold set.

### 9. Orchestration failures

**Mechanism.** Coordination = 36.94% of multi-agent failures ([augmentcode.com](https://www.augmentcode.com/guides/why-multi-agent-llm-systems-fail-and-how-to-fix-them)). Race conditions scale N(N-1)/2. Cursor parallel-agent bugs: merge conflicts silently reverted first agent's work; parallel agents fail to merge when Cursor opened in a subfolder ([forum.cursor.com](https://forum.cursor.com/t/parallel-agents-do-not-properly-merge-back-changes-when-working-on-subfolders-of-git-repo/150279)).

**Mitigation.** `SELECT FOR UPDATE SKIP LOCKED`-style task claiming. Validation gates on every handoff. Scoped file ownership per agent. For review agents (read-only), this is less severe but not zero — watch for shared-context corruption.

### 10. Cost blowups

**Mechanism.** Recursive agent-to-agent loops, no checkpointing, self-healing restart storms.

**Evidence.** [Kusireddy case](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/): **$47,000 invoice** from two agents exchanging messages for 11 days while everyone assumed they were working. Other reports: $47 on a single $0.80 pipeline run; $700 in 72h from 22 auto-restarts without checkpoint.

**Mitigation.** Circuit breakers tripping after N consecutive tool failures. Hard per-run token/$ budgets. Observability on message-exchange rate (not just API success). For `/double-check`: set `max_cost_usd` and `max_wall_clock_sec`, abort on trip.

### 11. Evaluation blind spots

**Mechanism.** Diff-bounded review is architecturally blind to: layer/boundary violations, latency/memory regressions, dependency risk, missing-feature bugs. Same-model generator+reviewer share blind spots; high coverage becomes "AI talking to itself" — self-correction on own output is documented as systematically reduced ([arXiv 2506.09443](https://arxiv.org/abs/2506.09443)).

**Mitigation.** Separate planning agent from generation agent. Cross-provider judge. Architecture-fitness tests **outside** the diff-review path. Dedicated dependency-risk agent with SCA tool integration.

### 12. Flakiness / non-determinism

**Mechanism.** Floating-point non-associativity, batched-inference load balancing, sampling. Identical input, different output. Seeds insufficient across hardware ([Thinking Machines "Defeating Nondeterminism"](https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/)). Downstream evidence: LLM-generated test flakiness is measurable ([arXiv 2601.08998](https://www.arxiv.org/pdf/2601.08998) — note this paper is about test flakiness, not inference mechanisms).

**Mitigation.** Temperature 0 + seed + fixed provider. Batch-invariant kernels (Thinking Machines approach) where available. Multi-run voting on high-severity findings — if a BLOCKING doesn't reproduce across 3 runs, it's probably noise.

---

## 4. Battle-Tested Performance Data

### Signal quality benchmarks

| Source | Config | Metric | Value |
|---|---|---|---|
| Anthropic internal ([blog](https://claude.com/blog/code-review)) | Multi-agent + verifier | FP rate | <1% |
| [Martian Code Review Bench](https://codereview.withmartian.com/) (17 tools, 200k+ PRs, released March 2026) | CodeRabbit | Precision / Recall / F1 | 49.2% / ~54% / 51.2% |
| Martian | CodeAnt AI | F1 | 51.7% (#3) |
| Qodo own benchmark (580 defects / 100 PRs) | Qodo 2.0 | Precision / Recall / F1 | — / 56.7% / 60.1% |
| [Augment benchmark](https://www.augmentcode.com/blog/we-benchmarked-7-ai-code-review-tools-on-real-world-prs-here-are-the-results) (50 PRs, 5 OSS repos) | Augment (best) | P / R / F | 65 / 55 / 59 |
| Augment benchmark | Copilot (worst) | P / R / F | 20 / 34 / 25 |
| [SWE-PRBench](https://arxiv.org/html/2603.26130v1) (350 PRs, 8 models) | Best model | Detection | 15–31%; hallucination 19–42% |
| [SWRBench](https://arxiv.org/abs/2509.01494) (1,000 PRs, 18 models) | Frontier models baseline | F1 | Best baseline 18.73% (PR-Review); Gemini-2.5-Flash with Self-Agg (n=10) reaches 21.91% (+43.67% relative) |

**Observation.** Vendor self-reports and academic benchmarks differ by an order of magnitude. Anthropic's <1% is likely measured against its own filtered output after the verifier; SWE-PRBench measures raw model detection vs ground-truth bug-fix PRs. Both are real; they're measuring different things.

### Cycle time impact (where it's been measured)

| Source | Metric | Before → After |
|---|---|---|
| HubSpot Sidekick | TTFF reduction | 90% (peak 99.76% Sep 2025) |
| HubSpot Sidekick | Engineer approval rate | 80%+ |
| [Atlassian Rovo Dev](https://www.atlassian.com/blog/announcements/how-we-cut-pr-cycle-time-with-ai-code-reviews) (internal) | PR cycle time | −45% |
| Atlassian Rovo Dev (customer beta) | PR cycle time | 4.18d → 2.85d (−32%) |
| Atlassian Rovo Dev | First-comment wait | 18h → 0 |
| Atlassian Rovo Dev | New-hire first PR merge | −5 days |
| Anthropic (internal) | Substantive review coverage | 16% → 54% |
| Greptile | Addressed-comment rate | 19% → 55%+ in 2 weeks |
| GitHub 2025 Octoverse (cited) | Merge speed | +32% in AI-assisted repos |
| GitHub 2025 Octoverse | Post-merge defect rate | −28% |

**Counter-evidence.** AI-authored PRs have 1.7× more issues, 1.4× more critical (CodeRabbit Dec 2025 report). METR RCT showed **19% slowdown** for some configurations.

### Cost at scale

| Tier | Cost |
|---|---|
| CodeRabbit Lite | $12 / user / mo |
| Qodo (standard) | $19 / user / mo |
| Qodo Enterprise | ~$45 / user / mo |
| Claude Code / Cursor / Codex Max tiers | $100–200 / user / mo |
| Self-hosted (50–200 devs) | $100k–$500k total; 12–18mo payback |
| Hidden senior-reviewer overhead | $510–960 / mo per senior |

Source: [Fordel 2026 coding-assistant cost analysis](https://fordelstudios.com/research/what-ai-coding-assistants-actually-cost-per-engineer-2026).

### Real gaps in public data (as of April 2026)

- No agent-count ablation curve (is 4 the knee? 5? 7? 9? nobody's published the curve).
- No severity-tier false-positive rates (what % of BLOCKING is actually blocking?).
- No 3+ month defect-escape retrospectives ("when the review ran, did it flag the bug that later escaped?").
- No per-model per-review token breakdowns on a fixed harness.

---

## 5. Cost Optimization Playbook

Ranked by impact × evidence quality.

### 1. Prompt caching (highest-impact lever)

**Mechanism.** Anthropic caches a prompt prefix keyed by exact token match. TTL: 5 min default, 1 hour optional (2× write premium). Min cacheable (current models, per [prompt caching docs](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching)): 4096 tokens (Opus 4.6/4.7, Haiku 4.5), 2048 (Sonnet 4.6), 1024 (older Sonnet/Opus). Up to 4 cache breakpoints per request.

**Savings.** Cache reads = 10% of base input cost; writes = 125% (5-min TTL) or 200% (1-hour). Anthropic's published figures: up to **90% input cost reduction, up to 85% latency reduction** on long prompts. For N parallel reviewers sharing a diff + system prompt, savings scale ~linearly with N.

**Implementation.** Order prefix as: `[static system + AGENTS.md + patterns + diff] → [per-reviewer lens + task]`. Set `cache_control` on the last block of the shared prefix. Fire all N reviewers within 5 min of the first (which warms the cache).

**Gotchas.** Cache key is exact-match — any whitespace or reordering busts it. File changes mid-review invalidate. Writes cost more than non-cached reads; single-shot use is net-negative.

Source: [docs.anthropic.com/en/docs/build-with-claude/prompt-caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching).

### 2. Batch API

**Mechanism.** Submit up to 100k requests; results within 24h (often <1h).

**Savings.** Flat **50% discount** on both input and output vs on-demand. Stacks with caching.

**Use cases.** Nightly scans of open PRs, retrospective codebase audits, backfilling reviews on a release branch.

**Bad for.** Interactive `/double-check` (async 24h defeats the purpose). No streaming, no tool use mid-batch, no reviewer→judge handoff in one run.

### 3. Model routing

**Pricing (per M tokens, April 2026).** Opus 4.6 $5 / $25. Sonnet 4.6 $3 / $15. Haiku 4.5 $1 / $5. GPT-5 base $1.25 / $10. Gemini 2.5 Pro $1.25 / $10.

**Savings.** All-Opus → Sonnet-reviewers + Opus-judge ≈ 70–80% input cost reduction on the reviewer phase. Adding Haiku triage for trivial diffs can drop another 60% on those paths. Anthropic advisor pattern: −11% total.

**Reference implementations.** Aider's leaderboard, Qodo's multi-model routing, Cursor's dynamic routing in agent mode.

**Caveat.** Orchestration complexity is real — you now maintain N prompts tuned to N models. Haiku's code reasoning is noticeably weaker on subtle bugs.

### 4. Diff truncation / PR compression

**Qodo pr-agent** ([github.com/qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent), see `pr_agent/algo/pr_processing.py` → `pr_generate_compressed_diff`):

- Rank files by change size
- Clip deleted-only hunks
- Remove boilerplate (lockfiles, minified JS, vendored deps, generated)
- Prioritize source over tests when over budget
- AST-rank changed functions
- Token-budget truncation per file

**Savings.** ~4× compression on large PRs with minimal signal loss (Qodo self-reported).

**Trade-off.** Truncation hides cross-file context. Randomized sampling loses determinism (can't diff outputs across runs).

### 5. Structured output (tool use / JSON mode)

**Mechanism.** Force fixed schema → eliminates prose preamble ("Here's my review…") and ambiguity.

**Savings.** Anecdotally 30–50% output token reduction on reviewer tasks when switching from markdown to tool-call output. No rigorous public benchmark.

**Implementation.** Define a `submit_review` tool with strict schema `{severity, file, line, message, verification_command?}`. Claude's `tool_choice: {type: "tool", name: "submit_review"}` forces the call.

**Trade-off.** Strict schemas can cut off nuance; reviewers may skip hard findings rather than force-fit.

### 6. Context assembly (changed-files + 1-hop import neighbors)

**Mechanism.** Ship only changed files plus direct import neighbors, not the whole repo. Aider's repo-map uses a ranked symbol graph. Sourcegraph Cody uses embeddings + graph. Cheapest: regex imports on changed files.

**Savings.** Aider repo-map reduces context **5–10×** vs full-repo on medium codebases.

**Trade-off.** Misses transitive impact, runtime-only deps, string-based DI.

Source: [aider.chat/docs/repomap.html](https://aider.chat/docs/repomap.html).

### 7. AGENTS.md / pattern files

**Mechanism.** Single source of truth for conventions. Loaded once, cached. The [agents.md](https://agents.md) spec emerged as the converging standard in late 2025; CodeScene and Cursor both adopted it.

**Savings.** If conventions are ~2k tokens and you run 8 reviewers/PR × 20 PRs/day = 320k tokens/day inlined. Caching drops it to effectively ~32k (10%). Real savings depend on cache hit rate.

**Implementation.** Route by file extension — only load `patterns/react.md` when `.tsx` in diff. Keep each pattern file under one cache block.

### 8. Per-agent context scoping

**Mechanism.** Security agent sees only auth/crypto/network-touching files; perf agent sees only hot-path changes.

**Savings.** If security-relevant files are 15% of diff, scoping cuts that agent's input ~85%.

**Implementation.** Pre-classify hunks via cheap Haiku pass or regex rules (`auth|token|crypto|exec|eval|session|secret|env|sql|shell|cookie`) and route.

**Trade-off.** Classifier errors = missed findings. Cross-cutting bugs (SSRF via a "UI" file) get missed.

### 9. Reviewer-judge prompt reuse

Shared system prompt (role-agnostic instructions + codebase context + diff) as cache prefix; per-reviewer lens as the only variable tail. Same math as #1 — shared prefix cached across N calls.

### 10. Deduplication at dispatch

Skip review entirely on formatting-only, lockfile-only, generated-file-only diffs. Frequency: 10–25% of PRs in monorepos with Prettier/Biome pre-commit.

Three detection methods (see also `/review-pr` skill):
- File extension allowlist
- AST equivalence check (format-preserving)
- `git diff --ignore-all-space` empty check

### 11. Circuit breakers & hard budgets (defense, not savings)

Given the $47k case study — hard budgets are existential, not optional.

- `max_cost_usd` per run — abort on trip
- `max_wall_clock_sec` per run
- N consecutive tool failures → halt
- Observability on message-exchange rate (not just API success)
- No recursive agent-to-agent loops without explicit termination proof

### 12. Stop conditions

Halt remaining reviewers once N blockers found. Potential savings: 20–30% if early-exit is common. Trade-off: loses signal for author ("fix these 3, but 5 more await"). Better suited to CI gate than author feedback loop.

---

**Highest-confidence, highest-impact stack**: prompt caching (#1) + model routing (#3) + structured output (#5) + batch for nightly (#2) + circuit breakers (#11). Combined: 80%+ cost reduction vs naive all-Opus real-time, with $47k-blowup defense.

---

## 6. Best Practices for Review Agent Context

### What to include in review prompts

1. **Scope the diff precisely** — feature branch diff vs base, not the whole repo.
2. **One agent, one job** — "Fix OAuth redirect loop in `src/lib/auth.ts`" succeeds; "Fix authentication" fails.
3. **Explicit success criteria** — each subagent knows output format, severity ranking, what to skip.
4. **File references always** — agents without paths waste turns exploring.
5. **Project conventions via pattern files** — stored in `docs/patterns/` or `AGENTS.md`, routed by file extension, cached.
6. **Git SHA range** — provide base and head commits so the reviewer sees exactly what changed.
7. **Verification commands** — for every finding, require a shell/grep/AST command that proves the claim (CodeRabbit pattern).

### Handling conflicting feedback across agents

- **Rank by severity across all agents** — BLOCKING > SHOULD-FIX > WATCH > NIT, regardless of source.
- **Categorize** — Issues (must fix) vs Suggestions (nice to have).
- **Deduplicate** — Multiple agents flag the same problem from different angles; synthesizer merges.
- **Promote to high-confidence** when ≥2 agents independently flag the same finding.
- **Verdict logic** — All tests pass + no BLOCKING/SHOULD-FIX = Ready. WATCH only = Needs Attention. BLOCKING or failing tests = Needs Work.

### What NOT to review with agents

- Formatting-only changes (detect and skip — see §5.10)
- Lock files, generated code, build artifacts
- IDE configuration, sourcemaps, binary files

### Severity definitions (to prevent over-classification)

- **BLOCKING** = runtime failure, security issue, data loss, invisible breakage
- **SHOULD-FIX** = correctness, type safety, test gaps, inconsistency
- **WATCH** = documented trade-offs, fragile patterns, scope concerns
- **NIT** = style, naming, cosmetic

---

## 7. Single vs Multi-Agent: When It Matters

From [Qodo's analysis](https://www.qodo.ai/blog/single-agent-vs-multi-agent-code-review/):

| Scenario | Single-Agent | Multi-Agent |
|---|---|---|
| Small, focused PRs | Adequate | Overkill |
| Cross-repo / service changes | Misses system-level concerns | Specialized agents catch dependency impact |
| Security-sensitive changes | Generic feedback | Dedicated security + deployment agents |
| Large PRs / high volume | Quality degrades (context rot) | Remains predictable |

**Key failure mode of single-agent review at scale**: "As scope increases, the model focuses on what is easiest to infer from the diff and gives general feedback. System-level concerns are often left implicit."

---

## 8. External Tools and Frameworks (April 2026)

### Anthropic Code Review (Claude Code, March 2026)

See §1. Team/Enterprise only. $15–25/review. 54% PRs get substantive comments (up from 16%). Scales agent count with PR size. ~20 min wall-clock average.

### CodeRabbit

- Multi-agent: separate agents for analysis, verification, and grounding
- **Tool-based verification** — comments come with receipts (shell/ast-grep/python checks)
- **2M+ connected repositories** as of April 2026 (most complete and versatile AI review tool per comparisons)
- Supports GitHub, GitLab, Azure DevOps, Bitbucket + CLI
- Martian F1: 51.2%
- [coderabbit.ai](https://www.coderabbit.ai/)

### Qodo PR-Agent (open source) + Qodo 2.0 (commercial)

- **Raised $70M Series B, March 30, 2026** ([effloow](https://effloow.com/articles/best-ai-code-review-tools-coderabbit-claude-qodo-2026))
- Layered architecture: user interfaces → orchestration → specialized tools → platform abstraction
- Commands: `/review`, `/describe`, `/improve`, `/ask`
- PR compression strategy (see §5.4) manages token usage, truncates patches
- **Qodo 2.0** agentic code review: 4 specialized agents (bugs / quality / security / tests), F1 60.1%
- Qodo reflect prompt is **the only fully-published production judge prompt** ([github.com/qodo-ai/pr-agent](https://github.com/qodo-ai/pr-agent))
- Commercial tier adds `/compliance`, `/test`, `/implement`, static analysis

### Greptile

- 0–5 PR confidence + **embedding-based comment filter** (cosine similarity to past up/downvoted comments)
- 19% → 55%+ addressed-comment rate in 2 weeks after deploying filter
- Only production-deployed "learn-from-past-feedback" variant documented

### CodeScene (Guard Rails)

- Code Health MCP server: objective maintainability signals as tools agents can call during coding
- **AGENTS.md pattern**: encodes intended tool sequencing and decision logic
- Research: AI-coding assistants increase defect risk 30%+ in unhealthy codebases. Need Code Health ≥ 9.5 for safe AI operation.
- MCP-guided agents: 2–5× more Code Health improvements vs raw refactoring
- [codescene.com](https://codescene.com/blog/agentic-ai-coding-best-practice-patterns-for-speed-with-quality)

### GitHub Copilot Code Review

- Agentic architecture as of March 2026
- Built into GitHub PR flow
- Caveat: Augment benchmark ranked it worst (P/R/F 20/34/25) — widest vendor-vs-independent gap in the space

### Cursor 2.0

- Up to 8 agents in parallel via git worktrees or remote machines
- Dedicated agent layout; agents/plans/runs are first-class sidebar objects
- Known bug: parallel-agent subfolder merge ([forum.cursor.com](https://forum.cursor.com/t/parallel-agents-do-not-properly-merge-back-changes-when-working-on-subfolders-of-git-repo/150279))

### CodeAnt AI

- F1 51.7% on Martian bench (#3 ranked)
- Strong coverage guide on review-overload defense ([codeant.ai](https://www.codeant.ai/blogs/prevent-ai-code-review-overload))

### Atlassian Rovo Dev

- Documented case study: **45% PR cycle time reduction internal**, 32% in customer beta
- First-comment wait 18h → 0
- [atlassian.com](https://www.atlassian.com/blog/announcements/how-we-cut-pr-cycle-time-with-ai-code-reviews)

### DeepSource & Kodus-AI

Expanded coverage as of April 7, 2026 per landscape updates. Less data publicly available.

---

## 9. Claude Code Subagent Configuration

State as of April 2026 (version 2.1.101+, versions 2.1.69–2.1.101 shipped in the last 3 weeks).

### Complete frontmatter reference

```yaml
---
name: code-reviewer            # required: lowercase + hyphens
description: when to delegate  # required: used by Claude to route
tools: Read, Grep, Glob, Bash  # optional: explicit allowlist
disallowedTools: Write, Edit   # optional: denylist (applied after tools)
model: sonnet                  # sonnet | opus | haiku | full ID | inherit
permissionMode: default        # default | acceptEdits | auto | dontAsk | bypassPermissions | plan
maxTurns: 20                   # cap on agentic turns
skills: [brainstorming]        # preloaded skill content
mcpServers: [github, slack]    # MCP access scoped to this subagent
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./validate-readonly.sh"
memory: project                # user | project | local — persistent memory scope
background: true               # always run as background task
effort: high                   # low | medium | high | xhigh | max
isolation: worktree            # temporary git worktree copy, auto-cleanup
color: blue                    # UI display color
initialPrompt: "Review..."     # auto-submitted first turn when run as --agent
---
```

All fields except `name` and `description` optional. `Agent` tool was renamed from `Task` in v2.1.63; `Task(...)` still works as alias.

### Parallel dispatch mechanics

- **Tool**: `Agent` tool — dispatches subagent with its own context window.
- **Concurrency**: no hard published limit; each subagent has independent model context.
- **Allowlist spawnable agent types** via `tools: Agent(worker, researcher)` syntax.
- **Only main-thread sessions** (run via `--agent`) can spawn subagents. **Subagents cannot nest.**
- **Result return**: subagent transcripts stored at `~/.claude/projects/{project}/{sessionId}/subagents/agent-{agentId}.jsonl`; results summarized back to main conversation.

### Read-only reviewer pattern

```yaml
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, NotebookEdit
permissionMode: plan  # enforces read-only at permission layer too
```

Layer a `PreToolUse` hook on `Bash` as a runtime safety net beyond `disallowedTools`. Hook script receives JSON via stdin with `tool_input.command`; exit 2 blocks, exit 0 passes.

### Hook types relevant to review

- **PreToolUse** — before tool execution; can block (exit 2), modify input, or allow.
- **PostToolUse** — after tool success; can block result or inject context.
- **Stop** — when subagent finishes → converted to `SubagentStop` at runtime.
- **SubagentStart** (session-level) — fires when subagent spawned; matcher is agent type name.
- **SubagentStop** (session-level) — fires when subagent completes.

Exit codes: 0 = allow/pass, 2 = deny/block with stderr message.

### Model routing

Resolution order:
1. `CLAUDE_CODE_SUBAGENT_MODEL` env var
2. Per-invocation `model` parameter (if Claude passes one)
3. Subagent definition's `model` frontmatter
4. Main conversation's model

**No single-shot "reviewer=Sonnet, judge=Opus" field.** Achieve via two distinct subagent definitions with different `model` fields.

### Memory / knowledge base

| Scope | Location | Notes |
|---|---|---|
| `user` | `~/.claude/agent-memory/<name>/` | Cross-project learnings |
| `project` | `.claude/agent-memory/<name>/` | Project-specific, version-controllable |
| `local` | `.claude/agent-memory-local/<name>/` | Project-specific, not version-controlled |

- Persists across sessions in same project.
- Does **not** persist across different Agent tool invocations within a single session unless you use `SendMessage` to resume.
- System prompt includes first 200 lines or 25 KB of `MEMORY.md`.

### Background execution

- **Frontmatter**: `background: true` always launches as background task.
- **Runtime**: `run_in_background: true` on Agent tool call, or Ctrl+B.
- Main session can continue while background subagent works.
- **Notification hook** (`Notification` event) fires on completion.
- **Permission behavior**: background subagents auto-deny any permission not pre-approved. If it hits a denied permission mid-task, that tool call fails but subagent continues (no interactive prompts).
- **Disable all**: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`.

### Worktree isolation

`isolation: worktree` → subagent gets temporary git worktree (isolated copy of repo).

- **Auto-cleanup** if subagent makes no changes (fixed April 2026).
- Subagent cannot access files outside its worktree (permissions restricted) — **fixed April 2026** for own-worktree file access.
- Worktree path changes do not affect main session's cwd.
- Results (diffs, summaries) flow back to main conversation. No auto-merge.

### Headless / CI mode

`claude --agent <name>` runs the session as that subagent (main thread inherits its system prompt, tool restrictions, model).

- `--dangerously-skip-permissions` — skip all checks (applies to all subagents spawned by lead). **Fixed April 2026**: previously silently downgraded to accept-edits after approving a write to a protected path.
- `--disallowedTools "Agent(name)"` — restrict agent spawning.
- Exit codes: 0 success, non-zero failure. Output: JSON lines to stdout.
- Official GitHub integration lives under the Code Review feature.

### Agent Teams (still experimental, April 2026)

- Requires v2.1.32+ and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
- Lead session creates team, spawns teammates (separate Claude Code instances).
- Shared task list + mailbox for inter-agent messaging.
- Teammates message each other directly or broadcast.
- **vs. Subagents**: subagents report back to main only; teammates communicate peer-to-peer. Each teammate has independent context.
- **Display modes**: in-process (default, Shift+Down to cycle) or split-panes (tmux/iTerm2 required).

**Known limitations.**
- No session resumption with in-process teammates.
- Task completion status can lag.
- Slow shutdown.
- One team per session.
- No nested teams.

### Prompt caching for subagents

- **Automatic** for Claude Sonnet/Opus/Haiku if prefix is ≥1024 tokens (2048 for Haiku) and repeats exactly.
- No explicit configuration needed.
- Subagents in parallel that share project context benefit automatically.
- Cache hit rates not published by Anthropic.

### MCP integrations for code review

Popular in 2026:
- `github` — PR diffs, issue context, commit history
- `slack` — thread notifications, team feedback
- `jira` (Atlassian MCP) — linked tickets, acceptance criteria
- `context7` — live docs (README, CONTRIBUTING, design docs)
- Custom analyzers — ESLint, tsc, test runners, SAST tools
- **CodeScene Code Health MCP** — objective maintainability signals

Use `mcpServers` in subagent frontmatter to scope reviewer-only MCP access.

### Known gotchas

- **State leakage**: subagents inherit main conversation's permissions. `bypassPermissions` at lead propagates.
- **Nesting forbidden**: subagents cannot spawn subagents. Use chaining or Agent Teams.
- **Tool conflicts**: two subagents editing the same file in parallel → overwrites. Scope file ownership.
- **Memory not shared across invocations**: spawning same subagent twice creates two instances.
- **Race conditions**: Agent Teams use file locking for task claiming; safe but status can lag.
- **MCP tool inheritance** was buggy with dynamically-injected servers; fixed April 2026.

### April 2026 changelog highlights (v2.1.69 → v2.1.101)

- `/agents` tabbed layout: **Running tab** shows live subagents with `● N running` indicator; **Library tab** adds Run and View-running actions
- `refreshInterval` status line setting (re-run every N seconds)
- Focus view toggle (Ctrl+O) in `NO_FLICKER` mode: prompt + one-line tool summary with edit diffstats + final response
- Syntax highlighting for Cedar policy files (`.cedar`, `.cedarpolicy`)
- `/reload-plugins` now picks up plugin-provided skills without restart
- Vim mode: j/k in NORMAL mode navigate history and select footer pill
- Fixed: `--dangerously-skip-permissions` downgrade bug
- Fixed and hardened: Bash tool permissions around env-var prefixes and network redirects

Sources: [Claude Code changelog](https://code.claude.com/docs/en/changelog), [claudelog.com/claude-code-changelog](https://claudelog.com/claude-code-changelog/), [Apiyi April 2026 overview](https://help.apiyi.com/en/claude-code-changelog-2026-april-updates-en.html).

---

## 10. Installed Superpowers Skills

(Unchanged from prior reference — still current.)

### superpowers:requesting-code-review

Dispatches `code-reviewer` subagent with crafted context: what was implemented, plan/requirements, git SHA range. Reviews return categorized issues (Critical, Important, Minor) with binary verdict.

### superpowers:receiving-code-review

6-step process: READ → UNDERSTAND → VERIFY → EVALUATE → RESPOND → IMPLEMENT.

Forbidden: "You're absolutely right!", "Great point!", implementing before understanding.
Required: restate technical requirement, ask clarifying questions, push back with reasoning.

Implementation priority: Clarify unclear → Blocking → Simple fixes → Complex fixes.
YAGNI check: grep codebase for usage; if unused, recommend removal over implementing reviewer's suggestion.

### superpowers:verification-before-completion

Gate: IDENTIFY command → RUN it → READ full output → VERIFY claim → ONLY THEN claim success.

Red flags: "should", "probably", "seems to", satisfaction before verification, trusting agent success reports without VCS diff check.

### superpowers:code-reviewer (subagent)

Responsibilities: plan alignment → code quality → architecture → docs → issue categorization (Critical → Important → Suggestions).

Template placeholders for custom dispatch: `{WHAT_WAS_IMPLEMENTED}`, `{PLAN_OR_REQUIREMENTS}`, `{BASE_SHA}`, `{HEAD_SHA}`, `{DESCRIPTION}`.

Output format: Strengths → Issues (by severity) → Recommendations → Assessment → Production Readiness.

### superpowers:subagent-driven-development

Two-stage review per task: spec compliance → code quality. Fix-and-re-review loops until both pass. Final full review after all tasks. Flows into `finishing-a-development-branch`.

Red flags: start on main without consent, skip either review stage, dispatch multiple implementers in parallel, make subagent read plan file directly, start quality review before spec passes.

### superpowers:dispatching-parallel-agents

For 3+ independent investigations. Pattern: independent domains → focused agent tasks → dispatch → review summaries → verify no conflicts → run full suite.

### review-pr

PR review guide generator. Categorizes files into CRITICAL / HIGH / MEDIUM / SKIP tiers. Detects AI red flags (over-engineering, hallucinated imports, shallow tests). Mode selection: PR number → `gh pr view/diff`, branch → `git diff main...branch`.

Formatting-only detection: diff inspection (whitespace-normalized line equivalence), commit-message signal, stat-only heuristic.

### simplify (code-simplifier)

Post-review cleanup. Reduces nesting, eliminates redundancy, consolidates logic. Never changes behavior. Avoids nested ternaries, prefers clarity over brevity, refines only recently-modified code unless instructed.

### superpowers:finishing-a-development-branch

Presents structured options for merge, PR, or cleanup after implementation and reviews pass.

### Complete pipeline

```
verification-before-completion
    → requesting-code-review (dispatches code-reviewer subagent)
    → receiving-code-review (handle feedback)
    → verification-before-completion (verify fixes)
    → merge
```

---

## 11. Installable Skills from skills.sh

(As of April 1, 2026. Not refreshed — install counts may have drifted.)

| Skill | Installs | Install Command |
|-------|----------|----------------|
| `skillcreatorai/ai-agent-skills@code-review` | 961 | `npx skills add skillcreatorai/ai-agent-skills@code-review -g -y` |
| `rysweet/amplihack@quality-audit-workflow` | 56 | `npx skills add rysweet/amplihack@quality-audit-workflow -g -y` |
| `wyattowalsh/agents@honest-review` | 53 | `npx skills add wyattowalsh/agents@honest-review -g -y` |
| `oimiragieo/agent-studio@subagent-driven-development` | 28 | `npx skills add oimiragieo/agent-studio@subagent-driven-development -g -y` |
| `arinhubcom/arinhub@ah-review-code` | 19 | `npx skills add arinhubcom/arinhub@ah-review-code -g -y` |
| `saturate/claude@codebase-audit` | 18 | `npx skills add saturate/claude@codebase-audit -g -y` |
| `yuniorglez/gemini-elite-core@code-review-pro` | 12 | `npx skills add yuniorglez/gemini-elite-core@code-review-pro -g -y` |
| `arinhubcom/arinhub@arinhub-code-reviewer` | 11 | `npx skills add arinhubcom/arinhub@arinhub-code-reviewer -g -y` |
| `moodmnky-llc/mood-mnky-command@code-review` | 9 | `npx skills add moodmnky-llc/mood-mnky-command@code-review -g -y` |
| `doubleuuser/rlm-workflow@rlm-subagent` | 9 | `npx skills add doubleuuser/rlm-workflow@rlm-subagent -g -y` |

---

## 12. Implementation Recipes

### Recipe 1: Minimal viable multi-agent review

1. `.claude/agents/code-reviewer.md` with read-only tools, `model: sonnet`, `permissionMode: plan`, `PreToolUse` hook on Bash
2. `/code-review` command dispatching 3–5 parallel subagents (spec, regression, adversarial, security-conditional, perf-conditional)
3. Judge step in main thread — Sonnet, with metadata-redacted input
4. Project conventions in `AGENTS.md` or `docs/patterns/` — routed by file extension
5. `memory: project` on reviewer so it learns over time

### Recipe 2: Two-stage review per task (subagent-driven development)

```
Per task:
  1. Dispatch implementer subagent
  2. Implementer implements, tests, commits, self-reviews
  3. Dispatch spec reviewer → Issues? → Implementer fixes → Re-review
  4. Dispatch quality reviewer → Issues? → Implementer fixes → Re-review
  5. Mark task complete
  6. Final: dispatch code-reviewer subagent for entire implementation
```

Model selection:
- Mechanical implementation (isolated functions, clear specs) → Haiku / Sonnet
- Integration (multi-file coordination) → Sonnet
- Architecture / design / review → Opus or Sonnet-as-judge (see §2)

### Recipe 3: Parallel investigation of multiple failures

```
1. Identify independent problem domains (group failures by root cause)
2. Create focused agent tasks (one per domain, specific scope, clear goal)
3. Dispatch all in parallel (run_in_background: true)
4. Review each summary, verify no conflicts
5. Run full test suite
```

### Recipe 4: PR review guide generation

```
1. Run review-pr skill with PR number or branch name
2. Files auto-categorized into CRITICAL / HIGH / MEDIUM / SKIP
3. Per-file guidance generated for CRITICAL and HIGH only
4. AI red flags detected; output to .reviews/ or inline
```

### Recipe 5: Judge with bias mitigation (new)

```
Per review:
  1. Reviewers receive: diff + branch name + commit messages (intent context)
  2. Judge receives: reviewer findings ONLY — metadata stripped
  3. Judge prompt:
     - System: "Evaluate each finding on succinctness/accuracy/actionability.
                Apply hard caps: max 7 on 'verify X', max 8 on error handling,
                0 on type hints alone. For each finding, require a
                verification_command that proves the claim."
     - Temperature: 0.2
     - Structured output: JSON with {suggestion_score, why, verification_command, action}
     - 1-shot example of a well-graded finding
  4. Judge uses a different model family than reviewers if available;
     else a different system prompt framing
  5. Post only findings with score ≥ threshold AND verification_command that runs clean
  6. If zero findings pass, emit single-line "clean, ship it" — silence is a feature
```

### Recipe 6: Cost-optimized review pipeline (new)

```
1. Detect diff scope; skip if formatting-only / lockfile-only (see §5.10)
2. Compress diff with AST ranking + boilerplate removal (§5.4)
3. Load pattern files by extension (§5.7)
4. Build shared prefix: [system + patterns + compressed diff]
5. Set cache_control on last shared block
6. Dispatch N parallel reviewers (Sonnet), each with per-lens tail
7. All within 5 min to hit warm cache
8. Judge (Sonnet) synthesizes; structured output
9. Circuit breakers on max_cost_usd + max_wall_clock (§5.11)
10. For nightly retrospectives: use Batch API (§5.2) — 50% cheaper
```

### Recipe 7: Defense against prompt injection (new)

```
1. Treat diff content as untrusted data, never instructions
2. Strip unicode control chars before feeding to reviewers
3. Never allow reviewers to auto-approve or auto-edit
4. permissionMode: plan on reviewer subagents
5. For rule / config / .cursor / .vscode file changes, flag for human-only review
6. Use scoped MCP — reviewer agents get no shell/network access beyond read
7. Log every tool call; monitor for unusual patterns
```

---

## 13. What Humans Should Still Review

From [Daniela Petruzalek (Google Cloud)](https://medium.com/google-cloud/how-to-do-code-reviews-in-the-agentic-era-0b6584700f47) and [Sean Goedecke](https://www.seangoedecke.com/ai-agents-and-code-review/), extended with April 2026 findings:

- **Architecture & system design** — hardcoded values, oversimplification, premature complexity. Diff-bounded review is architecturally blind here.
- **Public APIs** — interface ergonomics, hard-to-misuse design.
- **Algorithms & data structures** — AI defaults to naive approaches.
- **Dependencies** — every new package is a security / maintenance risk.
- **The code that *could have been* written** — whether existing systems could have been reused instead of building new ones.
- **Prompt-injection-adjacent changes** — rule files, config, `.cursor`, `.vscode` — human-review by default (CVE-2025-53773 precedent).
- **AI-authored PRs** — 1.7× more issues, 1.4× more critical than human-authored; deserve extra scrutiny.

---

## 14. Recommendations

Ordered by impact × evidence quality.

1. **Adopt the judge pattern with bias mitigations.** Metadata-redact before judging. Use Sonnet-as-judge (Opus only if quality gap matters). Structured output with required `why` + `verification_command`. Hard category caps. CoT before verdict. Low temperature (0.2–0.3). (§2)

2. **Deploy prompt caching with explicit breakpoints.** Shared prefix `[system + patterns + diff]` + `cache_control` + per-reviewer tail. Fire reviewers within 5 min. Potential 90% input cost reduction. (§5.1)

3. **Add circuit breakers and hard per-run budgets.** `max_cost_usd`, `max_wall_clock_sec`, N-consecutive-failure halt. Defense against $47k-case loops. (§5.11)

4. **Require tool-based verification for every third-party claim.** CodeRabbit pattern — comments come with receipts. Kills grep-is-not-proof and hallucinated-finding classes. (§2, §3.1, §3.2)

5. **Store conventions in AGENTS.md or `docs/patterns/`, route by file extension.** Emerging standard. Pattern files cached once, loaded by lens relevance. (§5.7)

6. **Skip review on formatting-only diffs.** Detect via diff normalization, commit-message signal, or stat-only heuristic. 10–25% of PRs in monorepos. (§5.10)

7. **Use Batch API for nightly scans** (50% cheaper). Keep interactive `/double-check` on real-time API. (§5.2)

8. **Treat diff content as untrusted data.** Strip unicode control chars. Never auto-approve. Flag rule/config changes for human-only review. CVE-2025-53773 defense. (§3.5, Recipe 7)

9. **Use a cross-family judge where possible.** If same-provider lock-in, at least use different system prompts / framings. Defense against documented same-model self-correction gaps ([arXiv 2506.09443](https://arxiv.org/abs/2506.09443)). (§3.8)

10. **Wire headless review into CI.** `claude --agent code-reviewer` for automated PR checks. Pair with human review; AI complements, doesn't replace. (§9)

---

## 15. Sources

### Official Documentation
- [Code Review for Claude Code (Anthropic blog)](https://claude.com/blog/code-review)
- [Claude Code Subagent Docs](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Changelog](https://code.claude.com/docs/en/changelog)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Agent Teams (Experimental)](https://code.claude.com/docs/en/agent-teams)
- [Anthropic Prompt Caching Docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- [claude-code GitHub releases](https://github.com/anthropics/claude-code/releases)
- [Apiyi: Claude Code April 2026 Changelog Overview](https://help.apiyi.com/en/claude-code-changelog-2026-april-updates-en.html)
- [ClaudeLog Changelog](https://claudelog.com/claude-code-changelog/)

### Product Blogs & Case Studies
- [Anthropic Code Review (The New Stack)](https://thenewstack.io/anthropic-launches-a-multi-agent-code-review-tool-for-claude-code/)
- [Anthropic launches Code Review (TechCrunch, 2026-03-09)](https://techcrunch.com/2026/03/09/anthropic-launches-code-review-tool-to-check-flood-of-ai-generated-code/)
- [HubSpot Automated Code Review: 6-Month Evolution](https://product.hubspot.com/blog/automated-code-review-the-6-month-evolution)
- [HubSpot Sidekick (InfoQ, March 2026)](https://www.infoq.com/news/2026/03/hubspot-ai-code-review-agent/)
- [HAMY: 9 Parallel AI Agents That Review My Code](https://hamy.xyz/blog/2026-02_code-reviews-claude-subagents)
- [Atlassian: How We Cut PR Cycle Time by 45% with AI Reviews](https://www.atlassian.com/blog/announcements/how-we-cut-pr-cycle-time-with-ai-code-reviews)
- [Greptile: Embedding Filter Case Study (ZenML)](https://www.zenml.io/llmops-database/improving-ai-code-review-bot-comment-quality-through-vector-embeddings)
- [Qodo: Introducing Qodo 2.0 Agentic Code Review](https://www.qodo.ai/blog/introducing-qodo-2-0-agentic-code-review/)
- [Qodo: Single-Agent vs Multi-Agent](https://www.qodo.ai/blog/single-agent-vs-multi-agent-code-review/)
- [Qodo: Why Your AI Code Reviews Are Broken](https://www.qodo.ai/blog/why-your-ai-code-reviews-are-broken-and-how-to-fix-them/)
- [Qodo: When Claude Code Reviews Its Own PR](https://www.qodo.ai/blog/when-claude-code-reviews-its-own-pr-who-reviews-claude/)
- [CodeRabbit: Accurate Reviews on Massive Codebases](https://www.coderabbit.ai/blog/how-coderabbit-delivers-accurate-ai-code-reviews-on-massive-codebases)
- [CodeRabbit: Tops Martian Benchmark](https://www.coderabbit.ai/blog/coderabbit-tops-martian-code-review-benchmark)
- [Effloow: Best AI Code Review Tools 2026](https://effloow.com/articles/best-ai-code-review-tools-coderabbit-claude-qodo-2026)
- [CodeScene: Agentic AI Patterns](https://codescene.com/blog/agentic-ai-coding-best-practice-patterns-for-speed-with-quality)
- [agents.md spec](https://agents.md)

### Academic & Benchmarks
- [Martian Code Review Bench (17 tools, 200k+ PRs, March 2026)](https://codereview.withmartian.com/)
- [SWE-PRBench (arXiv 2603.26130)](https://arxiv.org/html/2603.26130v1)
- [SWR-Bench PR-Review (arXiv 2509.01494)](https://arxiv.org/html/2509.01494v1)
- [Evaluating LLMs for Code Review (arXiv 2505.20206)](https://arxiv.org/html/2505.20206v1)
- [Don't Judge Code by Its Cover — biases (arXiv 2505.16222)](https://arxiv.org/html/2505.16222v1)
- [Confirmation bias in LLM security review (arXiv 2603.18740)](https://arxiv.org/html/2603.18740)
- [Agent-as-a-Judge (arXiv 2410.10934)](https://arxiv.org/html/2410.10934v2)
- [LLMs Cannot Reliably Judge Yet (arXiv 2506.09443)](https://arxiv.org/html/2506.09443v1)
- [Multi-Agent Debate with Stability Detection (arXiv 2510.12697)](https://arxiv.org/html/2510.12697v1)
- [Ranked Voting Self-Consistency (arXiv 2505.10772)](https://arxiv.org/html/2505.10772v1)
- [LLM-as-Judge Bias (arXiv 2510.12462)](https://arxiv.org/html/2510.12462v1)
- [On the Flakiness of LLM-Generated Tests (arXiv 2601.08998)](https://www.arxiv.org/pdf/2601.08998)
- [Hallucination Detection via AST (arXiv 2601.19106)](https://arxiv.org/html/2601.19106v1)
- [Your AI, My Shell — prompt injection (arXiv 2509.22040)](https://arxiv.org/html/2509.22040v1)
- [Augment Benchmark: 7 Tools Compared](https://www.augmentcode.com/blog/we-benchmarked-7-ai-code-review-tools-on-real-world-prs-here-are-the-results)
- [Towards Practical Defect-Focused AI Code Review (OpenReview)](https://openreview.net/forum?id=mEV0nvHcK3)

### Failure Modes & Defense
- [The $47,000 AI Agent Loop Case Study](https://earezki.com/ai-news/2026-03-23-the-ai-agent-that-cost-47000-while-everyone-thought-it-was-working/)
- [earezki: How I Built a Multi-Agent Review Pipeline (April 13, 2026)](https://earezki.com/ai-news/2026-04-13-how-i-built-a-multi-agent-code-review-pipeline/)
- [CVE-2025-53773: Copilot RCE via Prompt Injection](https://embracethered.com/blog/posts/2025/github-copilot-remote-code-execution-via-prompt-injection/)
- [Datadog: Stopping Hackerbot — Malicious PRs](https://www.datadoghq.com/blog/engineering/stopping-hackerbot-claw-with-bewaire/)
- [Why Multi-Agent LLM Systems Fail — Augment](https://www.augmentcode.com/guides/why-multi-agent-llm-systems-fail-and-how-to-fix-them)
- [Cursor parallel-agent subfolder bug](https://forum.cursor.com/t/parallel-agents-do-not-properly-merge-back-changes-when-working-on-subfolders-of-git-repo/150279)
- [diffray: LLM Hallucinations in Code Review](https://diffray.ai/blog/llm-hallucinations-code-review/)
- [LLM Judges Are Unreliable — CIP](https://blog.cip.org/p/llm-judges-are-unreliable)
- [Jet Xu: Drowning in AI Code Review Noise](https://jetxu-llm.github.io/posts/low-noise-code-review/)
- [CodeAnt: Prevent AI Code Review Overload](https://www.codeant.ai/blogs/prevent-ai-code-review-overload)
- [Morph: Context Rot](https://www.morphllm.com/context-rot)
- [Thinking Machines: Defeating Nondeterminism in LLM Inference](https://thinkingmachines.ai/blog/defeating-nondeterminism-in-llm-inference/)
- [Find Dead Code in Golang Monorepo (grep failure modes)](https://www.codestudy.net/blog/find-dead-code-in-golang-monorepo/)
- [repowise — grep-enrichment for agents](https://github.com/repowise-dev/repowise)
- [augmentedswe: AI Code Review Security](https://www.augmentedswe.com/p/ai-code-review-security)

### Human Review in the AI Era
- [Code Reviews in the Agentic Era (Petruzalek, Google Cloud)](https://medium.com/google-cloud/how-to-do-code-reviews-in-the-agentic-era-0b6584700f47)
- [AI Agents and Code Review (Sean Goedecke)](https://www.seangoedecke.com/ai-agents-and-code-review/)
- [AI Code Looks Fine Until the Review Starts (CodeRabbit report, Dec 2025)](https://www.helpnetsecurity.com/2025/12/23/coderabbit-ai-assisted-pull-requests-report/)

### Cost Optimization
- [Anthropic Batch API](https://docs.anthropic.com/en/docs/build-with-claude/batch-processing)
- [Claude Code Advisor Strategy (MindStudio)](https://www.mindstudio.ai/blog/claude-code-advisor-strategy-opus-sonnet-haiku)
- [GPT-5 vs Gemini 2.5 Pro Pricing (Artificial Analysis)](https://artificialanalysis.ai/models/comparisons/gpt-5-vs-gemini-2-5-pro)
- [Aider Repo Map](https://aider.chat/docs/repomap.html)
- [Aider Benchmarks](https://aider.chat/docs/leaderboards/)
- [Qodo PR-Agent Source (compression pipeline)](https://github.com/qodo-ai/pr-agent)
- [Qodo pr-agent reflect prompt (verbatim)](https://github.com/qodo-ai/pr-agent/blob/main/pr_agent/settings/code_suggestions/pr_code_suggestions_reflect_prompts.toml)

### Tools (April 2026)
- [CodeRabbit](https://www.coderabbit.ai/)
- [Qodo](https://www.qodo.ai/)
- [Greptile](https://www.greptile.com/)
- [CodeScene](https://codescene.com/)
- [Cursor](https://www.cursor.com/)
- [GitHub Copilot Code Review (agentic)](https://github.blog/changelog/2026-03-05-copilot-code-review-now-runs-on-an-agentic-architecture/)
- [skills.sh (skill registry)](https://skills.sh/)

### Cost at Scale
- [Fordel: AI Coding Assistant Costs Per Engineer 2026](https://fordelstudios.com/research/what-ai-coding-assistants-actually-cost-per-engineer-2026)

### Secondary Coverage
- [The New Stack coverage](https://thenewstack.io/anthropic-launches-a-multi-agent-code-review-tool-for-claude-code/)
- [Help Net Security on Anthropic Code Review](https://www.helpnetsecurity.com/2026/03/10/anthropic-claude-code-review/)
- [GitHub Blog: Copilot Code Review Goes Agentic](https://github.blog/changelog/2026-03-05-copilot-code-review-now-runs-on-an-agentic-architecture/)
- [DEV: AI Code Review in Practice](https://dev.to/mcrolly/ai-code-review-in-practice-how-devops-teams-are-cutting-pr-cycle-time-with-claude-and-codex-4bja)
- [Anthropic 2026 Agentic Coding Trends Report (PDF)](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
