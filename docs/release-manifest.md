# Release Manifest

Each successful staging deployment writes:

```text
releases/<release-id>/release.json
```

The manifest records the deployed release identity and framework versions:

```json
{
  "deployment_id": "mel-staging",
  "repository": "git@github.com:anna-pye/myeventlane-platform.git",
  "branch": "staging",
  "commit": "current git commit",
  "release_id": "20260703194512",
  "framework_version": "0.1.0-dev",
  "planner_version": "1",
  "policy_version": "1",
  "deployment_profile": "staging",
  "created_at": "2026-07-03T09:45:12Z",
  "status": "deployed"
}
```

The executor also writes a structured deployment log to:

```text
logs/<release-id>.deployment.json
```

The log records start, finish, duration, step results, errors, and rollback status.
