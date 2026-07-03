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
- Doctor validates read-only environment check contracts in mock mode.
- Health evaluates supplied health state before and after release activity.
- Executor prepares staging releases, invokes mock plugins, switches `current` atomically, and writes release logs.
- Rollback restores the previous `current` symlink after post-switch validation failure.

## Boundary

Only staging execution is implemented. Production deployment and production rollback are forbidden. The executor does not run SSH, rsync, SCP, real Composer, real Drush, or hardcoded credentials.
