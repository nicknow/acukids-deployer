#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
generated=$(mktemp)
trap 'rm -rf "$test_root" "$generated"' EXIT

# Extract only the generated apply script; do not execute the installer.
awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-apply.sh"/ { found=1; next }
     found && /^APPLY_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$generated"

export ACUKIDS_LIBRARY_MODE=true
export ACUKIDS_HOME="$test_root/acukids"
mkdir -p "$ACUKIDS_HOME/config" "$ACUKIDS_HOME/state/last-applied/config"
printf 'version-a\n' > "$ACUKIDS_HOME/config/value"
cp "$ACUKIDS_HOME/config/value" "$ACUKIDS_HOME/state/last-applied/config/value"
printf '# test changelog\n' > "$ACUKIDS_HOME/CHANGELOG.md"

# shellcheck source=/dev/null
source "$generated"

require_root() { :; }
apply_all() {
  record_last_applied_state
}

printf 'version-b\n' > "$ACUKIDS_HOME/config/value"
snapshot_previous_state
record_last_applied_state
first_snapshot=$(cat "$STATE_DIR/LATEST")
[[ "$(cat "$STATE_DIR/$first_snapshot/config/value")" == "version-a" ]]

printf 'version-c\n' > "$ACUKIDS_HOME/config/value"
snapshot_previous_state
record_last_applied_state
second_snapshot=$(cat "$STATE_DIR/LATEST")
[[ "$(cat "$STATE_DIR/$second_snapshot/config/value")" == "version-b" ]]
[[ "$(cat "$STATE_DIR/$second_snapshot/PARENT")" == "$first_snapshot" ]]

rollback
[[ "$(cat "$ACUKIDS_HOME/config/value")" == "version-b" ]]
[[ "$(cat "$STATE_DIR/LATEST")" == "$first_snapshot" ]]

rollback
[[ "$(cat "$ACUKIDS_HOME/config/value")" == "version-a" ]]
[[ ! -e "$STATE_DIR/LATEST" ]]

echo "apply rollback: OK"
