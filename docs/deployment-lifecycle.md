# Deployment Lifecycle

The deployment framework is split into reusable readiness phases followed by a staging-only executor.

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Planner
    ↓
Policy
    ↓
Dry Run
    ↓
Doctor
    ↓
Health
    ↓
Layout Verification
    ↓
Report
    ↓
Staging Executor
    ↓
Rollback when post-switch validation fails
```

## Current Phases

- Manifest defines local deployment intent and contains no secrets.
- Validation checks manifest shape, schema, path strings, and local repository metadata.
- Resolution converts a validated manifest into a canonical deployment model.
- Planner converts the resolved model into a deterministic execution plan.
- Policy evaluates whether the plan is allowed, warning, or blocked.
- Dry Run renders the plan as human-readable simulation text.
- Doctor validates profile-driven read-only environment checks.
- Health evaluates profile-configured health state before and after release activity.
- Layout verification validates required staging paths and shared resources without repair.
- Report summarises deployment readiness and blocking reasons.
- Executor prepares staging releases, validates immutable release integrity, invokes mock operation plugins, switches `current` atomically, and writes release logs.
- Rollback restores the previous `current` symlink after post-switch validation failure.

## Boundary

Only staging execution is implemented. Production deployment and production rollback are forbidden. The executor does not run SSH, rsync, SCP, real Composer install/update operations, Drush update/cache-rebuild operations, or hardcoded credentials. Release validation may run read-only `vendor/bin/drush status` from a prepared release root.
