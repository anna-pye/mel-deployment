# Server Doctor

Server Doctor is a read-only readiness framework for deployment environments.

Doctor validates configured check contracts for `staging` and `production` and returns deterministic human-readable and structured JSON output. CI and tests use non-network modes. Staging can opt into read-only SSH probes from the staging profile.

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
- PHP availability
- Composer availability
- Drush availability
- writable directories
- writable release root
- required directory layout
- deployment root existence
- releases directory existence
- shared directory existence
- current symlink existence
- logs directory existence
- readable shared resources
- required symlinks
- disk space
- permissions

Every check must declare a supported mode. `mock` validates the contract, `profile` validates required profile configuration, and `ssh` performs read-only remote checks. Unsupported modes fail closed.

## Non-Execution Guarantee

Doctor must not modify files, execute deployment steps, run Composer, run Drush, change symlinks, create releases, or write to staging or production.
