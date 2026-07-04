#!/usr/bin/env bash

mel_rollback_restore_current() {
  local current_link="$1"
  local previous_target="$2"
  local rollback_log="$3"

  python3 - "$current_link" "$previous_target" "$rollback_log" <<'PY'
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

current_link, previous_target, rollback_log = sys.argv[1:4]


def write_event(status, error=None):
    os.makedirs(os.path.dirname(rollback_log), exist_ok=True)
    event = {
        "status": status,
        "current": current_link,
        "restored_target": previous_target,
        "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if error is not None:
        event["error"] = error
    with open(rollback_log, "w", encoding="utf-8") as handle:
        json.dump(event, handle, indent=2)
        handle.write("\n")
    print(json.dumps(event, indent=2))


try:
    if not previous_target:
        raise OSError("previous current target is unknown")
    if os.environ.get("MEL_ROLLBACK_FORCE_FAIL") == "1":
        raise OSError("forced rollback failure")

    link_dir = os.path.dirname(current_link)
    os.makedirs(link_dir, exist_ok=True)
    fd, temp_link = tempfile.mkstemp(prefix=".current.", dir=link_dir)
    os.close(fd)
    os.unlink(temp_link)
    os.symlink(previous_target, temp_link)
    os.replace(temp_link, current_link)
    write_event("rolled_back")
except OSError as exc:
    write_event("rollback_failed", str(exc))
    sys.exit(2)
PY
}
