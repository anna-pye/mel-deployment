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
- repository directory existence
- release integrity
- Drupal bootstrap through project-local Drush
- releases directory existence
- shared directory existence
- current symlink existence
- logs directory existence
- readable shared resources
- required symlinks
- disk space
- permissions

Every check must declare a supported mode. `mock` validates the contract, `profile` validates required profile configuration, and `ssh` performs read-only remote checks. Unsupported modes fail closed.

For live staging checks, Doctor distinguishes these failure classes:

- repository invalid: the canonical repository path from `repository_path` is missing or invalid.
- release invalid: the current release is missing required Drupal 11 release files.
- bootstrap failed: the release files are present, but `vendor/bin/drush status` fails from the release root.

Doctor does not use legacy Drupal 7 bootstrap files. Global Drush can be reported for availability, but release bootstrap is valid only through the current release's `vendor/bin/drush`.

## Non-Execution Guarantee

Doctor must not modify files, execute deployment steps, run Composer, run Drush update/cache-rebuild operations, change symlinks, create releases, or write to staging or production. Its only Drush use is read-only `vendor/bin/drush status` for bootstrap evidence when an SSH snapshot is enabled.
