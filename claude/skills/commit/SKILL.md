---
name: commit
description: "ONLY invoke when user explicitly runs /commit. Do NOT trigger on words like 'commit', 'save changes', 'create a commit', etc."
user-invocable: true
metadata:
  author: guido
  version: "1.0.0"
---

# /commit

Stage all, generate a commit message, commit. No prompts.

## Instructions

Do not ask the user anything — just do it. Minimize tool calls.

1. Run `git add -A && git diff --staged`.
2. From the diff output: if any file ends with `.env`, `.pem`, `.key`, `.p12`, `.pfx` or contains `secret`, `credential`, `password`, `token`, `private` in its name, abort and list those files.
3. If the diff is empty, say "nothing to commit" and stop.
4. Generate a concise commit message using Conventional Commits format (`type(scope): description`).
5. `git commit -m "<message>"` — no attribution of any kind. If it fails, show the error and stop.
