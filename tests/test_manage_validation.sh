#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
generated=$(mktemp)
apply_stub="$test_root/apply"
time_stub="$test_root/timekpra"
trap 'rm -rf "$test_root" "$generated"' EXIT

awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-manage.sh"/ { found=1; next }
     found && /^MANAGE_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$generated"

export ACUKIDS_LIBRARY_MODE=true
export ACUKIDS_HOME="$test_root/acukids"
mkdir -p "$ACUKIDS_HOME/config"
printf '[{"username":"alice","weekday_limit_seconds":3600,"weekend_limit_seconds":7200,"allowed_window":"06:00-19:00"}]\n' > "$ACUKIDS_HOME/config/children.json"
printf 'example.com\nexample.org\n' > "$ACUKIDS_HOME/config/whitelist-sites.conf"
printf 'example.desktop\n' > "$ACUKIDS_HOME/config/whitelist-apps.conf"
printf '{"admin_account":"administrator","original_installer_account":"fallback"}\n' > "$ACUKIDS_HOME/config/system-meta.json"
printf '# changelog\n' > "$ACUKIDS_HOME/CHANGELOG.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$apply_stub"
chmod +x "$apply_stub"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" > "%s/timekpra.args"\n' "$test_root" > "$time_stub"
chmod +x "$time_stub"

# shellcheck source=/dev/null
source "$generated"
require_root() { :; }
APPLY="$apply_stub"
PATH="$test_root:$PATH"

for invalid in 'BadName' 'ab' 'bad name' 'alice'; do
  if (add_child "$invalid" 1234); then
    echo "invalid or duplicate child accepted: $invalid" >&2
    exit 1
  fi
done
if (add_site 'https://example.net'); then
  echo "URL accepted as a domain" >&2
  exit 1
fi
if (add_app 'terminal;rm.desktop'); then
  echo "unsafe desktop filename accepted" >&2
  exit 1
fi

remove_site example.com
grep -qxF example.org "$CONFIG_DIR/whitelist-sites.conf"
! grep -qxF example.com "$CONFIG_DIR/whitelist-sites.conf"

reset_time alice
grep -Eq '^--settimeleft alice = (3600|7200)$' "$test_root/timekpra.args"

echo "manage validation: OK"
