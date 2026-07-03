# Executor

The Executor is the first staging-only deployment runtime for `mel-deployment`.

It supports only:

- repository: `anna-pye/myeventlane-platform`
- environment: `staging`
- deployment root: the value configured by `profiles/staging.json`

Production execution is forbidden. `mel execute production` returns `MEL_EXECUTOR_PRODUCTION_FORBIDDEN` before validation, planning, filesystem changes, plugin calls, or rollback logic can run.

## Pipeline

`mel execute staging` always runs the established framework layers in order:

```text
Validation
    ↓
Resolution
    ↓
Planner
    ↓
Policy
    ↓
Doctor
    ↓
Health
    ↓
Layout Verification
    ↓
Executor
```

Any failure stops the deployment and returns exit code `2`.

## Layout

The staging profile owns the deployment root and path layout. The default staging profile resolves to `/home/mel/staging`.

The required structure is:

```text
/home/mel/staging/
  releases/
  shared/
  current -> releases/<release-id>
  logs/
```

Dry-runs validate the profile and pipeline without requiring the live path to exist. Real execution verifies the directories and `current` symlink before creating a release.

The executor reads `paths.releases`, `paths.shared`, `paths.current`, and `paths.logs` from the profile, falling back to directories under `deployment_root` only when an older profile omits explicit path keys.

The executor reads the canonical repository path from `repository_path`. The default staging profile sets this to `/home/mel/staging-repo`, intentionally keeping the source repository outside the immutable release tree under `/home/mel/staging`.

## Release Preparation

Release IDs use deterministic timestamp format:

```text
YYYYMMDDHHMMSS
```

The executor creates:

```text
releases/<release-id>/
```

It copies runtime repository contents from `repo/` into the release and excludes repository metadata, CI, tests, documentation, examples, and temporary files.

`current` is not changed during release preparation.

Before release health checks and before switching `current`, the executor validates release integrity. A release must contain:

- `composer.json`
- `vendor/autoload.php`
- `vendor/bin/drush`
- `web/core/lib/Drupal.php`
- `web/index.php`

The release must also execute `vendor/bin/drush status` successfully from the release root. This is a Drupal 11 release contract; legacy Drupal 7 bootstrap files are not accepted.

Prepared releases are immutable. If validation fails, the release is rejected and the deployment stops. Operators must replace the broken release with a corrected one instead of repairing it in place, preserving auditability and keeping rollback behavior deterministic.

## Plugins

The executor uses the existing plugin framework. Composer, Drush, shared resource linking, health, and current switching are invoked through plugin contracts.

This phase supports mock Composer and Drush operation plugins only. The executor does not run SSH and does not embed Composer install/update or Drush update/cache-rebuild commands. The only project Drush command in the executor path is the read-only release validation command `vendor/bin/drush status`.

## Rollback

After `current` is switched, post-switch validation runs. If validation fails, the executor restores the previous `current` symlink and records a rollback event in `logs/<release-id>.rollback.json`.
