# First Staging Deployment Report

Date: 2026-07-03
Environment: staging
Repository: `anna-pye/myeventlane-platform`
Framework version: `0.1.0-dev`
Commit audited: `b294b783a014995d55fe86b85f54d3a771520537`

## Outcome

Status: stopped before real deployment.

No production action was attempted. No staging filesystem mutation was attempted. The real deployment command `mel execute staging` was not run because the audit could not verify a live staging environment with the current framework configuration.

## Validation Results

Static validation passed.

```text
bash -n deploy/lib/*.sh
bash -n deploy/bin/*
bash tests/run-tests.sh
132 passed, 0 failed
```

Staging audit commands completed successfully, but the checks were profile-based rather than live remote checks.

```text
mel doctor staging
Status: passed
Mode: profile

mel verify staging
Status: passed
profile: passed
layout: passed
health: passed

mel report staging
Deployment Ready: READY
Doctor Status: passed
Health Status: passed
Layout Status: passed
Policy Status: allowed
```

Dry-run completed successfully.

```text
mel execute staging --dry-run
status: passed
release_id: 20260703043901
staging_root: /home/mel/staging
```

The rendered execution plan was:

```text
10 validate
20 prepare_release
30 link_shared
40 composer_install
50 database_update
60 cache_rebuild
70 health_check
80 switch_current
```

## Deployment Details

Release ID: not deployed. The dry-run release ID was `20260703043901`.
Commit deployed: not deployed. The audited commit was `b294b783a014995d55fe86b85f54d3a771520537`.
Deployment duration: not applicable because real deployment was stopped before execution.

## Health Summary

Profile health checks reported passed for:

- `staging_http_response`
- `staging_drupal_status`
- `staging_root`

These checks did not prove live HTTP response, cache rebuild, or a complete live deployment run. The framework now distinguishes read-only `vendor/bin/drush status` bootstrap evidence from mutable Drush update/cache-rebuild operations.

## Rollback Status

Rollback was not exercised because no real deployment occurred.

Rollback could not be guaranteed for a real staging deployment from this workstation because the framework has not proven the live staging `current` symlink or previous release target through live checks.

## Issues Encountered

- `profiles/staging.json` uses `doctor_checks` with `mode: "profile"`, so `mel doctor staging` validates configured fields rather than the real staging server.
- `profiles/staging.json` uses `verification.mode: "profile"`, so `mel verify staging` does not inspect the live `/home/mel/staging` layout.
- `deploy/plugins/*.plugin.json` declare `executes: false`, and `docs/executor.md` confirms Composer install/update, Drush update/cache-rebuild, health, and current-switch plugins are mock contracts in this phase.
- `docs/staging-deployment.md` explicitly states this phase does not support real Composer install/update or Drush update/cache-rebuild operations.
- Because the objective was the first real staging deployment, these profile/mock checks are insufficient evidence to proceed safely.

## Follow-up Actions

- Decide whether staging deployment should run on the staging host itself or be driven remotely over SSH.
- Convert staging doctor checks to live checks before a real deployment gate is considered satisfied.
- Add live verification for `/home/mel/staging-repo`, `/home/mel/staging/releases`, `/home/mel/staging/shared`, `/home/mel/staging/current`, and `/home/mel/staging/logs`.
- Replace mock Composer and Drush operation contracts with audited Drupal 11 safe execution steps, or explicitly document that this framework only switches pre-built releases.
- Re-run the full validation sequence after live staging verification is implemented.
