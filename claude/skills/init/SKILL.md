---
name: init
description: Use when starting work in a project that has no CLAUDE.md, or when asked to generate or improve a project's CLAUDE.md file.
user-invocable: true
metadata:
  author: guido
  version: "1.0.0"
---

# /init

Generate a concise, high-signal `CLAUDE.md` for the current project. Target: 10-30 lines. Every line must carry information that cannot be inferred from reading standard files.

**Do NOT use the Task tool (subagents). Process everything inline.**

## Step 1: Check preconditions

Run in parallel:
- Check for existing `CLAUDE.md` at the project root (`ls CLAUDE.md 2>/dev/null`)
- Read `~/.claude/CLAUDE.md` — build an exclusion list of topics already covered globally (wt, ESLint, TypeScript, attribution, etc.)

If `CLAUDE.md` already exists: read it and present it to the user. Use `AskUserQuestion`:
- "A CLAUDE.md already exists. What would you like to do?"
- Options: **Regenerate from scratch** / **Improve the existing one** / **Cancel**

## Step 2: Explore project

Run **Batch 1** in parallel:
1. `ls -1` at project root
2. Read `README.md` (first 80 lines only)
3. Read the root manifest — detect type and read whichever exists: `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`
4. Glob for: `AGENTS.md`, `CONTRIBUTING.md`, `.env.example`, `Makefile`, `Justfile`, `docker-compose*`, `Dockerfile`
5. Glob for monorepo indicators: `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `lerna.json`

Run **Batch 2** (based on Batch 1 results) in parallel:
- Read `CONTRIBUTING.md` if found
- Read `AGENTS.md` if found (any path)
- Read `.env.example` if found
- Read first CI workflow file found under `.github/workflows/`

## Step 3: Synthesize

Build the file from exactly 4 possible sections. **Omit any section with nothing non-obvious to say.**

### Section 1 — Purpose (always include)
One sentence. What is this repo? Extract from first paragraph of README or `package.json` description. If it's a monorepo, name the workspaces.

### Section 2 — Integration points (only if non-obvious)
Include only things Claude cannot infer from reading standard files:
- Non-obvious service wiring (e.g., "tmux hooks coordinate with Claude Code's `@claude_done` window option via Stop/Notification hooks in `claude/settings.json`")
- Private registry / auth setup not covered by global CLAUDE.md
- Database seeding / reset commands
- Environment variables with non-obvious purposes (from `.env.example`)
- Docker requirements or port conflicts
- If 2+ `AGENTS.md` files exist, reference them as the canonical doc source (see genomics-product pattern)

**Do NOT include:** file listings, symlink maps, which tools are installed, tech stack names (those are in `package.json`).

### Section 3 — Verify changes (always include)
The exact commands to confirm work is correct:
- Test, lint, typecheck, build — from manifest scripts or Makefile
- Any non-standard verification (e.g., `bash bin/wt-test`)
- Cross-reference CI workflows as the ground truth

### Section 4 — Project rules (only if they extend or override global CLAUDE.md)
- Methodology mandates (TDD, etc.)
- Required doc updates per change
- Tool/plugin choices with rationale where the "obvious" alternative was deliberately rejected
- macOS-specific gotchas that affect cross-platform work

## Step 4: Filter (critical)

Before generating output, remove anything that:
- Duplicates a topic in `~/.claude/CLAUDE.md` (wt instructions, ESLint policy, attribution, TypeScript rules, etc.)
- Is inferable in one read from standard files (tech stack, file structure, which dependencies are installed)
- Is already documented well in README, SETUP.md, or CONTRIBUTING.md — reference the file instead of duplicating

## Step 5: Present and confirm

Show the full proposed `CLAUDE.md` in a code block.

Below the code block, add one sentence of rationale for each included section (why it's non-obvious and can't be inferred).

Use `AskUserQuestion`:
- "Write this CLAUDE.md to the project root?"
- Options: **Write it** / **Edit first (show me what to change)** / **Cancel**

## Step 6: Write

Use the `Write` tool to write `CLAUDE.md` at the project root. Print the path.

If this is the cockpit repo, remind the user to add the new file to `sync.sh` if they want it backed up.

---

## Common mistakes to avoid

| Natural tendency | Why it's wrong |
|---|---|
| Include a file/path mapping table | Inferable from `sync.sh` or `ls` — adds ~15 lines of noise |
| List installed skills / tools by name | Directory listing — zero information density |
| Repeat wt, ESLint, or attribution rules | Already in `~/.claude/CLAUDE.md` — wastes context |
| Add a section for every component | Only include what Claude would get wrong without it |
| Document "how to install" or "how it works" | That belongs in README/SETUP.md |
