---
name: test-driven-development
description: Apply test-first development to suitable behavior changes while respecting the project's test and production-code boundaries.
---

# Test-driven development

Use test-first development when the requested behavior has a practical,
maintainable automated test boundary.

1. Identify the smallest observable behavior and the branches that should be
   covered, including error and boundary cases.
2. Add or update the focused test before the production change when practical.
3. Do not run tests, builds, or formatters without separate user confirmation.
   Never claim that a test fails or passes unless that result was actually
   observed; otherwise describe the expected result as unverified.
4. After an authorized failing-test observation, make the minimal production
   change needed for the requested behavior, then request confirmation before
   running the relevant test again.
5. Avoid brittle tests tied to incidental implementation details.

If the user asks only to write or add tests, do not modify production code.
Do not force TDD onto documentation, configuration, generated files, or changes
without a useful automated test boundary; explain the limitation instead.
