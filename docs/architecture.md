# Architecture

mel-deployment currently implements a local validation engine. It is not a deployment runtime.

## Principles

- One executable, `deploy/bin/mel`, owns the command interface.
- New behavior should be exposed through subcommands, not additional binaries.
- Validation libraries live under `deploy/lib/` and are reusable by future phases.
- The engine fails with structured `success`, `warning`, or `error` output and stable exit codes.
- No current command may deploy, roll back, connect to servers, run SSH, run rsync, run Composer, run Drush, or modify remote filesystems.

## Components

- `deploy/bin/mel` routes `validate`, `info`, and `version` subcommands.
- `deploy/lib/common.sh` provides shared repository and version helpers.
- `deploy/lib/errors.sh` defines status names, error codes, and exit codes.
- `deploy/lib/output.sh` formats command results and details.
- `deploy/lib/manifest.sh` loads and validates manifests.
- `deploy/lib/schema.sh` validates JSON schema and manifest structure.
- `deploy/lib/paths.sh` validates path strings.

## Validation Flow

`mel validate` performs these checks in order:

1. Repository metadata validation confirms the local repository has required validation-engine files.
2. Schema validation confirms the configured schema is parseable and has the expected top-level shape.
3. Manifest validation confirms the manifest is parseable and matches the bundled schema.
4. Path validation checks manifest path strings without probing local or remote filesystems.

## Path Policy

Path validation rejects:

- empty paths
- relative paths
- parent-directory traversal with `..`
- duplicate separators
- root directory `/`

The engine does not validate server path existence in this phase.

## Non-Goals

This phase intentionally excludes deployment, rollback, SSH, rsync, Composer, Drush, filesystem modification, remote access, and server validation.
