---
name: verification-before-completion
description: Verify changes before reporting completion, separating allowed read-only checks from builds, tests, and formatters that require confirmation.
---

# Verification before completion

Base completion claims on current evidence.

Perform relevant read-only checks without additional confirmation, such as:

- inspect the final diff and repository status;
- re-read changed code and its callers for scope and consistency;
- search for stale references, conflict markers, unintended files, and obvious
  configuration or line-ending problems;
- inspect file modes and declarative metadata without changing the index.

Before compiling, building, running tests, executing formatters, or invoking a
command that materially changes repository or external state, obtain explicit
user confirmation. Do not treat prior runs as proof for the current changes.

Report exactly which checks were performed and their results. List every
relevant build, test, formatter, runtime, platform, or integration check that
was not run, and describe the result as unverified rather than successful.
