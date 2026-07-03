# Architecture

mel-deployment implements local validation, resolution, planner, policy, dry-run, doctor, health, plugin-contract, and staging executor frameworks.

## Principles

- One executable, `deploy/bin/mel`, owns the command interface.
- New behavior should be exposed through subcommands, not additional binaries.
- Validation, resolution, planner, policy, dry-run, doctor, health, plugin, executor, release, rollback, and release manifest libraries live under `deploy/lib/` and are reusable by future phases.
- The engine fails with structured `success`, `warning`, or `error` output and stable exit codes.
- Production execution is forbidden. The staging executor does not run SSH, rsync, real Composer, real Drush, or hardcoded credentials.

## Components

- `deploy/bin/mel` routes `validate`, `resolve`, `plan`, `policy`, `dry-run`, `doctor`, `verify`, `report`, `execute`, `info`, and `version` subcommands.
- `deploy/lib/common.sh` provides shared repository, usage, and version helpers.
- `deploy/lib/errors.sh` defines status names, error codes, and exit codes.
- `deploy/lib/output.sh` formats command results and details.
- `deploy/lib/manifest.sh` loads and validates manifests.
- `deploy/lib/schema.sh` validates JSON schema and manifest structure.
- `deploy/lib/paths.sh` validates path strings.
- `deploy/lib/resolver.sh` converts validated manifests into canonical deployment models.
- `deploy/lib/planner.sh` converts resolved deployment models into deterministic execution plans.
- `deploy/lib/policy.sh` evaluates read-only deployment policy from a plan and profile.
- `deploy/lib/dryrun.sh` renders a plan as simulation text without executing it.
- `deploy/lib/doctor.sh` validates mock doctor contracts for staging and production.
- `deploy/lib/health.sh` evaluates supplied health state for supported checks.
- `deploy/lib/readiness.sh` validates staging profile, layout, health, and deployment readiness reports.
- `deploy/lib/plugins.sh` validates non-executable plugin interface contracts.
- `deploy/lib/executor.sh` orchestrates the staging deployment pipeline.
- `deploy/lib/releases.sh` prepares releases, verifies layout, and links shared resources.
- `deploy/lib/rollback.sh` restores the previous `current` symlink after post-switch validation failure.
- `deploy/lib/release_manifest.sh` writes release manifests and structured deployment logs.

## Validation Flow

`mel validate` performs these checks in order:

1. Repository metadata validation confirms the local repository has required engine files.
2. Schema validation confirms the configured schema is parseable and has the expected top-level shape.
3. Manifest validation confirms the manifest is parseable and matches the bundled schema.
4. Path validation checks manifest path strings without probing local or remote filesystems.

## Resolution Flow

`mel resolve` performs these checks in order:

1. Repository metadata validation confirms the local repository has required engine files.
2. The existing validation engine validates the manifest and path strings.
3. Resolution normalises values, applies documented defaults, and resolves canonical path aliases.
4. Conflict detection rejects ambiguous or unsupported configuration.
5. The canonical deployment model is emitted as deterministic formatted JSON.

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Canonical Deployment Model
```

## Planner Flow

`mel plan` performs these checks in order:

1. Repository metadata validation confirms the local repository has required engine files.
2. The existing validation engine validates the manifest and path strings.
3. The existing resolution engine emits the canonical deployment model.
4. Planning calculates deterministic steps, orders, actions, and dependencies.
5. Plan validation rejects impossible or unsupported execution graphs.
6. The execution plan is emitted as deterministic formatted JSON.

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Planner
    ↓
Execution Plan
```

## Readiness Flow

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
Doctor
    ↓
Health
    ↓
Layout Verification
    ↓
Staging Executor
    ↓
Rollback when post-switch validation fails
```

Policy evaluates environment, local repository state, deployment profile, approvals, validation success, and planner success. Dry-run renders the plan only. Doctor validates profile-driven check definitions and can perform read-only SSH checks when the profile opts into them. Health checks are read from the profile and evaluated without hardcoded URLs. Layout verification returns structured failures and never repairs. The staging executor reuses those layers before preparing a release.

## Staging Executor Flow

`mel execute staging` supports only the staging environment and reads its deployment root and layout paths from `profiles/staging.json`. It verifies the required `repo/`, `releases/`, `shared/`, `current`, and `logs/` layout before mutation.

The executor creates `releases/<release-id>/`, copies runtime repository contents from `repo/`, links profile-defined shared resources, invokes mock plugins for Composer, Drush, health, shared resources, and current switching, writes `release.json`, writes `logs/<release-id>.deployment.json`, and switches `current` atomically only after all pre-switch checks pass.

## Staging Verification Flow

`mel verify staging` is read-only. It validates:

1. Staging profile structure.
2. Configured layout paths.
3. Required shared resources.
4. Configured health checks.

`mel report staging` combines validation, resolution, planner, policy, doctor, health, and layout results into a deployment readiness report. Deployment readiness is `READY` only when every blocking check passes.

If post-switch validation fails, rollback restores the previous `current` symlink and records `logs/<release-id>.rollback.json`.

## Path Policy

Path validation rejects:

- empty paths
- relative paths
- parent-directory traversal with `..`
- duplicate separators
- root directory `/`

The engine does not validate server path existence in this phase. Resolution may derive canonical path values from `repository.root`, but it does not create or inspect those paths.

## Non-Goals

This phase intentionally excludes production deployment, production rollback, SSH commands, rsync, SCP, real Composer execution, real Drush execution, remote modification, hardcoded credentials, and hardcoded SSH configuration.
