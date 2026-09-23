# Working on MapleBridge

## Scope

- Read README.md first. This is an early-stage Windows / AWS WireGuard project for GMS.
- Default routing must cover GMS and Nexon Launcher traffic while keeping unrelated traffic direct. Evaluate process and domain rules as described in docs/harness.md; do not silently substitute a full tunnel.
- Keep deployment repeatable, preserve existing keys, and make failures diagnosable.

## Workflow

- See [docs/harness.md](docs/harness.md) for the development workflow and check limitations.
- Keep changes small. Add dependencies and directories only when needed.
- Run checks appropriate to the change and report the commands, results, and any unverified behavior.
- Add behavioral tests as features arrive. Syntax checks alone do not prove functionality.

## Boundaries

- Local validation and CI must not access AWS, install software, or change networking.
- Keep AWS read-only checks separate from deployment and destructive operations. Neither exists yet.
- Only deploy, change live networking, or delete cloud resources when requested. Destructive commands must identify their targets and require explicit confirmation.
- Never commit secrets or print private keys. Keep generated state in ignored `state/` and local notes in ignored `working/`.
- Before publishing, review staged content and commit metadata for personal information, credentials, local paths, account IDs, and live infrastructure details. Use placeholders in examples and a GitHub noreply commit email. Ignore rules alone are not sufficient.
- Generate private keys on the machine that uses them. Normal updates must not rotate them.

## Documentation

- Use English for code comments and canonical documentation; keep README.zh-CN.md aligned with README.md.
- Keep local Chinese explanations in `working/` aligned when the corresponding English documents change.
- Document implemented behavior accurately and label planned features.
- Record significant decisions and their reasons when made; avoid duplicating documentation.
