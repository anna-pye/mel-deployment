# Changelog

## 0.1.0-dev

- Implement the `deploy/bin/mel` command with `validate`, `info`, and `version` subcommands.
- Add reusable validation libraries for common helpers, errors, output, manifests, schemas, and paths.
- Add a bundled manifest schema and default local validation manifest.
- Add deterministic validation tests and a local test runner.
- Update validation-only CI to run shell syntax checks, unit tests, and schema-backed manifest validation.
