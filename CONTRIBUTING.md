# Contributing Guide

Thanks for helping improve **zLineBot-automos**.

## Development setup
1. Install dependencies for your target area (`backend/api`, `backend/worker`, `frontend`, etc.).
2. Generate stack secrets for local integration testing:
   ```bash
   ./gen-secrets.sh example.local admin@example.local
   ```
3. Start local infrastructure:
   ```bash
   bash scripts/run-stack.sh up
   ```

## Branching and commits
- Use short topic branches.
- Keep commits focused and atomic.
- Follow conventional-style commit prefixes where possible (`fix:`, `feat:`, `docs:`, `chore:`).

## Quality checks
Run tests that correspond to your change:
```bash
pytest -q backend/api/tests
pytest -q backend/worker/tests
```

For shell changes:
```bash
rg --files -g '*.sh' | xargs -I{} bash -n '{}'
```

## Pull request checklist
- [ ] Tests updated or added.
- [ ] Documentation updated.
- [ ] Security implications considered.
- [ ] Backward compatibility reviewed.

## Documentation Refresh — 2026-03-26 (UTC)

- Revalidated contribution flow steps against current helper scripts and stack startup commands.
- Audit scope: repository-wide markdown and operational-documentation verification pass.

