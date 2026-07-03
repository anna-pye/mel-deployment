# Architecture

mel-deployment currently implements local validation, resolution, and planner engines. It is not a deployment runtime.

## Principles

- One executable, `deploy/bin/mel`, owns the command interface.
- New behavior should be exposed through subcommands, not additional binaries.
- Validation, resolution, and planner libraries live under `deploy/lib/` and are reusable by future phases.
- The engine fails with structured `success`, `warning`, or `error` output and stable exit codes.
- No current command may deploy, roll back, connect to servers, run SSH, run rsync, run Composer, run Drush, modify remote filesystems, or inspect remote systems.

## Components

- `deploy/bin/mel` routes `validate`, `resolve`, `plan`, `info`, and `version` subcommands.
- `deploy/lib/common.sh` provides shared repository, usage, and version helpers.
- `deploy/lib/errors.sh` defines status names, error codes, and exit codes.
- `deploy/lib/output.sh` formats command results and details.
- `deploy/lib/manifest.sh` loads and validates manifests.
- `deploy/lib/schema.sh` validates JSON schema and manifest structure.
- `deploy/lib/paths.sh` validates path strings.
- `deploy/lib/resolver.sh` converts validated manifests into canonical deployment models.
- `deploy/lib/planner.sh` converts resolved deployment models into deterministic execution plans.

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

## Path Policy

Path validation rejects:

- empty paths
- relative paths
- parent-directory traversal with `..`
- duplicate separators
- root directory `/`

The engine does not validate server path existence in this phase. Resolution may derive canonical path values from `repository.root`, but it does not create or inspect those paths.

## Non-Goals

This phase intentionally excludes deployment, rollback, SSH, rsync, Composer, Drush, filesystem modification outside caller-requested local output, remote access, server validation, repository inspection, release creation, directory creation, and execution of planned actions.
