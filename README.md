# mel-deployment

mel-deployment is the local validation and resolution foundation for a future deployment framework.

The current implementation validates manifests and resolves validated manifests into canonical deployment models. It does not deploy, roll back, connect to servers, run SSH, run rsync, run Composer, run Drush, modify remote filesystems, or perform release orchestration.

## Command Interface

Use the single executable:

```bash
deploy/bin/mel validate
deploy/bin/mel resolve --manifest examples/hold-production.yml
deploy/bin/mel info
deploy/bin/mel version
```

The framework is designed to scale through subcommands. Do not add separate binaries such as `mel-validate`, `mel-resolve`, or `mel-info`.

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

## Exit Codes

- `0` indicates `success`.
- `1` is reserved for `warning`.
- `2` indicates `error`.

## Repository Layout

- `.github/workflows/` contains validation-only GitHub Actions workflows.
- `deploy/bin/mel` is the single command entrypoint.
- `deploy/lib/` contains reusable shell validation and resolution libraries.
- `docs/` contains architecture and operational model documentation.
- `examples/` contains local example manifests and resolved models.
- `manifests/` contains the default local validation manifest.
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
```

Version: `0.1.0-dev`
