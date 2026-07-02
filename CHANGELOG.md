# Changelog

## 0.1.0-dev

- Implement the `deploy/bin/mel` command with `validate`, `resolve`, `info`, and `version` subcommands.
- Add reusable validation libraries for common helpers, errors, output, manifests, schemas, and paths.
- Add the local-only resolution engine for canonical deployment model generation.
- Add a bundled manifest schema and default local validation manifest.
- Add deterministic validation and resolver tests with a local test runner.
- Add hold-production example manifest and resolved canonical model artefacts.
- Update validation-only CI to run shell syntax checks, unit tests, schema-backed manifest validation, and resolver example validation.
