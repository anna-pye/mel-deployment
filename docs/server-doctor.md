# Server Doctor

Server Doctor is a read-only readiness framework for deployment environments.

In this phase, doctor runs in mock mode only. It validates configured check contracts for `staging` and `production` and returns deterministic human-readable and structured JSON output. It never contacts servers in CI or tests.

## Command

```bash
deploy/bin/mel doctor staging
deploy/bin/mel doctor production
deploy/bin/mel doctor staging --json
```

## Supported Checks

Profiles may define mock check contracts for:

- SSH connectivity
- PHP version
- Composer availability
- Drush availability
- writable directories
- required directory layout
- required symlinks
- disk space
- permissions

Every check must declare `"mode": "mock"` in this phase. Any other mode fails closed.

## Non-Execution Guarantee

Doctor must not modify files, execute deployment steps, run Composer, run Drush, change symlinks, create releases, or write to staging or production.
