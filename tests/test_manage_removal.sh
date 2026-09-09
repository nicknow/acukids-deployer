#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
generated=$(mktemp)
apply_stub="$test_root/apply"
trap 'rm -rf "$test_root" "$generated"' EXIT

awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-manage.sh"/ { found=1; next }
     found && /^MANAGE_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$generated"

export ACUKIDS_LIBRARY_MODE=true
export ACUKIDS_HOME="$test_root/acukids"
mkdir -p "$ACUKIDS_HOME/config"
printf '[{"username":"alice","weekday_limit_seconds":3600,"weekend_limit_seconds":7200,"allowed_window":"06:00-19:00"}]\n' > "$ACUKIDS_HOME/config/children.json"
printf 'example.com\n' > "$ACUKIDS_HOME/config/whitelist-sites.conf"
printf 'example.desktop\n' > "$ACUKIDS_HOME/config/whitelist-apps.conf"
printf '{"admin_account":"administrator","original_installer_account":"fallback"}\n' > "$ACUKIDS_HOME/config/system-meta.json"
printf '# changelog\n' > "$ACUKIDS_HOME/CHANGELOG.md"
printf '#!/usr/bin/env bash\nexit "${APPLY_RESULT:-0}"\n' > "$apply_stub"
chmod +x "$apply_stub"

# shellcheck source=/dev/null
source "$generated"
require_root() { :; }
deluser() { :; }
APPLY="$apply_stub"

export APPLY_RESULT=0
remove_child alice
[[ "$(jq length "$CHILDREN_JSON")" == 0 ]]

printf '[{"username":"alice","weekday_limit_seconds":3600,"weekend_limit_seconds":7200,"allowed_window":"06:00-19:00"}]\n' > "$CHILDREN_JSON"
export APPLY_RESULT=1
if (remove_child alice); then
  echo "removal unexpectedly succeeded after apply failure" >&2
  exit 1
fi
jq -e 'length == 1 and .[0].username == "alice"' "$CHILDREN_JSON" >/dev/null

echo "manage removal: OK"
