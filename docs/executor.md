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
  repo/
  releases/
  shared/
  current -> releases/<release-id>
  logs/
```

Dry-runs validate the profile and pipeline without requiring the live path to exist. Real execution verifies the directories and `current` symlink before creating a release.

The executor reads `paths.releases`, `paths.shared`, `paths.current`, and `paths.logs` from the profile, falling back to directories under `deployment_root` only when an older profile omits explicit path keys.

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

## Plugins

The executor uses the existing plugin framework. Composer, Drush, shared resource linking, health, and current switching are invoked through plugin contracts.

This phase supports mock plugins only. The executor does not embed Composer or Drush commands and does not run SSH.

## Rollback

After `current` is switched, post-switch validation runs. If validation fails, the executor restores the previous `current` symlink and records a rollback event in `logs/<release-id>.rollback.json`.
