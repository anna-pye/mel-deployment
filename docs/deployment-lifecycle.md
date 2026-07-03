# Deployment Lifecycle

The deployment-readiness framework is intentionally split into read-only phases before any future executor exists.

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
Executor (future)
    ↓
Rollback (future)
```

## Current Phases

- Manifest defines local deployment intent and contains no secrets.
- Validation checks manifest shape, schema, path strings, and local repository metadata.
- Resolution converts a validated manifest into a canonical deployment model.
- Planner converts the resolved model into a deterministic execution plan.
- Policy evaluates whether the plan is allowed, warning, or blocked.
- Dry Run renders the plan as human-readable simulation text.
- Doctor validates read-only environment check contracts in mock mode.

## Future Phases

Executor and rollback are not implemented in this repository phase. No current command may deploy, create releases, switch symlinks, run Composer, run Drush, rsync files, use SCP, or modify staging or production.
