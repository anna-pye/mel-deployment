# mel-deployment

mel-deployment is the local validation foundation for a future deployment framework.

The current implementation provides a reusable validation engine only. It does not deploy, roll back, connect to servers, run SSH, run rsync, run Composer, run Drush, modify remote filesystems, or perform release orchestration.

## Command Interface

Use the single executable:

```bash
deploy/bin/mel validate
deploy/bin/mel info
deploy/bin/mel version
```

The framework is designed to scale through subcommands. Do not add separate binaries such as `mel-validate` or `mel-info`.

## Validation Scope

`mel validate` performs local-only checks for:

- manifest loading
- schema validation
- path string validation
- repository metadata validation
- structured error output

Path validation rejects empty paths, relative paths, parent-directory traversal, duplicate separators, and `/`. It does not validate server path existence.

## Exit Codes

- `0` indicates `success`.
- `1` is reserved for `warning`.
- `2` indicates `error`.

## Repository Layout

- `.github/workflows/` contains validation-only GitHub Actions workflows.
- `deploy/bin/mel` is the single command entrypoint.
- `deploy/lib/` contains reusable shell validation libraries.
- `docs/` contains architecture and operational model documentation.
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
```

Version: `0.1.0-dev`
