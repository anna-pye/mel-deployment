# Tests

The `tests/` directory contains deterministic local tests for validation, resolution, and planning.

Run:

```bash
bash tests/run-tests.sh
```

The test runner covers:

- successful validation
- manifest, schema, and path validation errors
- successful resolution
- missing resolution values
- documented default resolution
- conflicting configuration
- duplicate deployment identifiers
- unsupported environments
- unsupported release strategies
- successful plan generation
- deterministic planner output
- dependency ordering
- duplicate step identifiers
- circular dependencies
- missing dependencies
- invalid planner actions
- invalid execution order
- malformed resolved models
- stable JSON output

Tests must not access the network, inspect servers, run SSH, run rsync, run Composer, run Drush, create releases, or deploy.
