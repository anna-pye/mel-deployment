# Security Model

The security model for this phase is fail-closed staging execution.

The executor supports only staging and rejects production before deployment logic runs. It does not manage credentials, hardcode secrets, hardcode SSH keys, open SSH connections, run rsync, run real Composer, or run real Drush.

All execution must pass validation, resolution, planner, policy, doctor, health, and layout verification before release activity. Post-switch validation failure triggers rollback to the previous `current` symlink.
