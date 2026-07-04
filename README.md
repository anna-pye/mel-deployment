# mel-deployment

mel-deployment is the local validation, resolution, planning, policy, dry-run, doctor, health, plugin-contract, and staging executor foundation for the MyEventLane deployment framework.

The current implementation validates manifests, resolves validated manifests into canonical deployment models, converts resolved models into deterministic execution plans, evaluates deployment policy, renders dry-run simulations, validates mock doctor contracts, evaluates supplied health state, validates plugin contracts, and can execute a staging-only atomic release workflow. It does not support production execution, production rollback, rsync, real Composer install/update execution, Drush update/cache-rebuild execution, hardcoded credentials, or hardcoded SSH keys. Staging readiness can use read-only SSH checks and project-local `vendor/bin/drush status` bootstrap validation when configured by the profile.

## Command Interface

Use the single executable:

```bash
deploy/bin/mel validate
deploy/bin/mel resolve --manifest examples/hold-production.yml
deploy/bin/mel plan --manifest examples/hold-production.yml
deploy/bin/mel policy --manifest examples/hold-production.yml --approval business --approval technical --approval release_manager
deploy/bin/mel dry-run --manifest examples/hold-production.yml
deploy/bin/mel doctor staging
deploy/bin/mel verify staging
deploy/bin/mel report staging
deploy/bin/mel execute staging --dry-run
deploy/bin/mel info
deploy/bin/mel version
```

The framework is designed to scale through subcommands. Do not add separate binaries such as `mel-validate`, `mel-resolve`, `mel-plan`, `mel-policy`, `mel-dry-run`, `mel-doctor`, or `mel-info`.

## Validation Scope

`mel validate` performs local-only checks for:

- manifest loading
- schema validation
- path string validation
- repository metadata validation
- structured error output

Path validation rejects empty paths, relative paths, parent-directory traversal, duplicate separators, and `/`. It does not validate server path existence.

## Resolution Scope

`mel resolve` performs:

- validation through the existing validation engine
- documented default application
- canonical path alias resolution
- conflict and ambiguity detection
- deterministic formatted JSON output

The resolution flow is:

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Canonical Deployment Model
```

See `docs/resolution-engine.md` for supported defaults and rejection rules.

## Planner Scope

`mel plan` performs:

- validation through the existing validation engine
- resolution through the existing resolution engine
- deterministic execution step ordering
- dependency calculation
- impossible sequence rejection
- formatted JSON plan output

The planning flow is:

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

See `docs/planner-engine.md` for the canonical plan format and rejection rules.

## Readiness And Execution Scope

- `mel policy` emits structured JSON only and evaluates environment, repository state, deployment profile, approvals, validation success, and planner success.
- `mel dry-run` prints a human-readable simulation from an execution plan and never executes the plan.
- `mel doctor` validates staging or production doctor contracts and can run profile-only or read-only SSH checks from profile configuration.
- `mel verify staging` validates staging profile, layout, and health readiness without repair or deployment.
- `mel report staging` prints a structured deployment readiness report with blocking reasons.
- `deploy/lib/health.sh` evaluates supplied health state for supported check types without hardcoded URLs.
- `deploy/lib/plugins.sh` validates non-executable plugin contracts in `deploy/plugins/`.
- `mel execute staging` runs the staging deployment pipeline through validation, resolution, planner, policy, doctor, health, layout verification, mock plugins, atomic current switching, release manifest generation, execution logging, and automatic rollback.
- `mel execute production` is explicitly forbidden and fails before any deployment logic runs.

See `docs/policy-engine.md`, `docs/dry-run.md`, `docs/server-doctor.md`, `docs/deployment-lifecycle.md`, `docs/executor.md`, `docs/staging-deployment.md`, `docs/staging-integration.md`, and `docs/release-manifest.md`.

## Exit Codes

- `0` indicates `success`.
- `1` is reserved for `warning`.
- `2` indicates `error`.

## Repository Layout

- `.github/workflows/` contains validation-only GitHub Actions workflows.
- `deploy/bin/mel` is the single command entrypoint.
- `deploy/lib/` contains reusable shell validation, resolution, planner, policy, dry-run, doctor, health, plugin-contract, executor, release, rollback, and release manifest libraries.
- `deploy/plugins/` contains non-executable plugin interface contracts.
- `docs/` contains architecture and operational model documentation.
- `examples/` contains local example manifests, resolved models, and execution plans.
- `manifests/` contains the default local validation manifest.
- `profiles/` contains non-secret staging and production deployment profiles.
- `schemas/` contains the bundled manifest schema.
- `tests/` contains deterministic local unit tests.

## Local Validation

Run:

```bash
bash -n deploy/lib/*.sh
bash -n deploy/bin/*
bash tests/run-tests.sh
deploy/bin/mel validate
deploy/bin/mel resolve --manifest examples/hold-production.yml
deploy/bin/mel plan --manifest examples/hold-production.yml
deploy/bin/mel dry-run --manifest examples/hold-production.yml
deploy/bin/mel doctor staging
deploy/bin/mel verify staging
deploy/bin/mel report staging
deploy/bin/mel execute staging --dry-run
```

Version: `0.1.0-dev`
