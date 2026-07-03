# Security Model

The security model for this phase is fail-closed staging execution.

The executor supports only staging and rejects production before deployment logic runs. It does not manage credentials, hardcode secrets, hardcode SSH keys, run rsync, run real Composer, or run real Drush.

Readiness verification can use read-only SSH probes only when the staging profile explicitly opts into them. Those probes must not create directories, modify files, change permissions, execute deployment steps, run Composer, or run Drush updates.

All execution must pass validation, resolution, planner, policy, doctor, health, and layout verification before release activity. Post-switch validation failure triggers rollback to the previous `current` symlink.
