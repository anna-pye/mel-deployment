# Changelog

## 0.1.0-dev

- Implement the `deploy/bin/mel` command with `validate`, `resolve`, `plan`, `info`, and `version` subcommands.
- Add reusable validation libraries for common helpers, errors, output, manifests, schemas, and paths.
- Add the local-only resolution engine for canonical deployment model generation.
- Add the local-only planner engine for deterministic execution plan generation.
- Add the read-only policy engine with structured `allowed`, `warning`, and `blocked` JSON decisions.
- Add the dry-run engine for human-readable execution plan simulation.
- Add mock-only server doctor contracts for staging and production.
- Add health and plugin contract frameworks without network, deployment, Composer, Drush, or symlink execution.
- Add non-secret staging and production deployment profiles.
- Add the staging-only executor with release preparation, shared resource linking, mock plugin invocation, atomic current switching, release manifests, structured execution logs, and automatic rollback.
- Add a bundled manifest schema and default local validation manifest.
- Add deterministic validation, resolver, planner, policy, dry-run, doctor, health, plugin, profile, executor, release manifest, and rollback tests with a local test runner.
- Add hold-production example manifest, resolved canonical model, and execution plan artefacts.
- Update validation-only CI to run shell syntax checks, unit tests, schema-backed manifest validation, resolver example validation, planner example validation, policy checks, dry-run simulation, mock doctor checks, staging executor dry-run, and production execution rejection.
