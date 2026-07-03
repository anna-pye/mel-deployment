# Staging Integration

This phase integrates the framework with staging readiness verification only. It does not deploy, create releases, repair directories, change permissions, switch symlinks, run Composer, or run Drush.

## Profile Structure

`profiles/staging.json` owns all staging-specific configuration:

- `profile_version`
- `repository`
- `ssh.host`
- `ssh.user`
- `deployment_root`
- `paths.releases`
- `paths.shared`
- `paths.current`
- `paths.logs`
- `shared_resources`
- `health_endpoints`
- `health_checks`
- `executables.php`
- `executables.composer`
- `executables.drush`

Secrets, credentials, SSH keys, and passwords must not be stored in the profile. The default profile uses a host alias so credentials remain in the operator's SSH configuration.

## Doctor Checks

`mel doctor staging` reads checks from the staging profile. Supported read-only checks include:

- SSH connectivity
- deployment root existence
- releases directory existence
- shared directory existence
- current symlink existence
- logs directory existence
- PHP availability
- Composer availability
- Drush availability
- writable release root
- readable shared resources

Doctor modes:

- `mock` validates the check contract only.
- `profile` validates that the required profile configuration exists.
- `ssh` runs read-only SSH probes such as `test`, `command -v`, and symlink checks.

Doctor must not create directories, modify files, change permissions, run deployment steps, run Composer, or run Drush updates.

## Layout And Health

`mel verify staging` validates profile, layout, and health readiness. Use focused checks when needed:

```bash
deploy/bin/mel verify staging --check layout --json
deploy/bin/mel verify staging --check health --json
```

Health checks are read from the staging profile. URLs and endpoints must not be hardcoded in the engine. Health failures block deployment readiness.

Layout verification returns structured failures and does not repair missing directories, shared resources, or symlinks.

## Report Format

`mel report staging` prints a human-readable summary followed by structured JSON:

```text
Deployment report
Environment: staging
Repository: git@github.com:anna-pye/myeventlane-platform.git
Framework Version: 0.1.0-dev
Profile Version: 1
Doctor Status: passed
Health Status: passed
Layout Status: passed
Policy Status: allowed
Deployment Ready: READY
```

If any blocking check fails, deployment readiness is `NOT READY` and the report lists blocking reasons.

## Readiness Lifecycle

The read-only staging readiness lifecycle is:

```text
Validation
    ↓
Resolution
    ↓
Planner
    ↓
Policy
    ↓
Doctor
    ↓
Health
    ↓
Layout
    ↓
Report
```

Only a `READY` report should allow a later deployment phase to proceed. This phase intentionally stops before deployment execution.
