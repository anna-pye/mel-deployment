# Tests

The `tests/` directory contains deterministic local tests for validation and resolution.

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
- stable JSON output

Tests must not access the network, inspect servers, run SSH, run rsync, run Composer, run Drush, create releases, or deploy.
