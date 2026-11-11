---
name: systematic-debugging
description: Diagnose bugs, failing tests, crashes, and unexpected behavior before proposing or implementing a fix.
---

# Systematic debugging

Use evidence to find the root cause before changing code.

1. Establish the expected and observed behavior from the request, existing tests,
   logs, diagnostics, and nearby code.
2. Reproduce the problem only when the required command is already authorized.
   Do not run builds, tests, or formatters without separate user confirmation.
3. Trace the failing path and narrow the first point where actual state diverges
   from expected state. Distinguish verified facts from hypotheses.
4. Check recent and related changes, callers, ownership, lifetimes, error paths,
   platform branches, and boundary values relevant to that point.
5. Prefer the smallest fix that addresses the verified cause. Do not hide the
   symptom, weaken validation, or broaden the task without user approval.
6. State what evidence supports the diagnosis and what remains unverified.

If safe read-only inspection cannot distinguish the remaining hypotheses, stop
and ask for the specific diagnostic action or information required.
