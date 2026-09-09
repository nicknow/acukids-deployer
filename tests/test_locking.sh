#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
generated=$(mktemp)
tmp=$(mktemp -d)
trap 'rm -rf "$generated" "$tmp"' EXIT
awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-apply.sh"/ { found=1; next }
     found && /^APPLY_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$generated"
export ACUKIDS_LIBRARY_MODE=true ACUKIDS_HOME="$tmp/acukids" LOCK_FILE="$tmp/lock"
source "$generated"
LOCK_FILE="$tmp/lock"

acquire_lock
acquire_lock
if (unset ACUKIDS_LOCK_HELD; bash -c "source '$generated'; LOCK_FILE='$tmp/lock'; acquire_lock") 2>"$tmp/error"; then
  echo "independent operation unexpectedly acquired the lock" >&2
  exit 1
fi
grep -q 'already running' "$tmp/error"

# The descriptor is kernel-managed: closing it releases the lock.
exec 9>&-
(unset ACUKIDS_LOCK_HELD; bash -c "source '$generated'; LOCK_FILE='$tmp/lock'; acquire_lock")
echo "locking: OK"
