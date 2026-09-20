# Development harness

The harness currently consists of repository context and a development workflow. There is no dedicated check runner or CI yet.

## Workflow

1. Read README.md for scope and AGENTS.md for working rules.
2. Identify the intended behavior and make a small, reviewable change.
3. Check the change using relevant tools directly. Review documentation links and consistency; check script syntax and test affected behavior when code exists.
4. Update affected documentation and local Chinese explanations. Record significant decisions and their reasons.
5. Report what changed, the exact checks and results, and what remains unverified.

## Growing the harness

Add repeatable behavioral tests alongside implemented features. Introduce CI or a shared check runner when recurring checks justify them. Document the actual commands here when they exist.

Keep offline checks separate from AWS read-only diagnostics and live operations. Default checks must not access AWS or modify networking. Syntax checks alone do not demonstrate that deployment or GMS routing works.
