#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
generated=$(mktemp)
trap 'rm -rf "$test_root" "$generated"' EXIT

awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-apply.sh"/ { found=1; next }
     found && /^APPLY_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$generated"

export ACUKIDS_LIBRARY_MODE=true
export ACUKIDS_HOME="$test_root/acukids"
mkdir -p "$ACUKIDS_HOME/config"
mkdir -p "$test_root/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/nmcli"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/resolvectl"
chmod +x "$test_root/bin/nmcli" "$test_root/bin/resolvectl"
export PATH="$test_root/bin:$PATH"
printf '[{"username":"alice","weekday_limit_seconds":3600,"weekend_limit_seconds":7200,"allowed_window":"06:00-19:00"}]\n' > "$ACUKIDS_HOME/config/children.json"
printf 'example.com\n' > "$ACUKIDS_HOME/config/whitelist-sites.conf"
printf 'example.desktop\n' > "$ACUKIDS_HOME/config/whitelist-apps.conf"
printf '[{"id":"example","label":"Example","url":"https://example.com/"}]\n' > "$ACUKIDS_HOME/config/homepage-links.json"
printf '# Homepage link IDs explicitly rejected by the owner.\n' > "$ACUKIDS_HOME/config/blacklist-homepage-links.conf"
printf 'WEEKDAY_LIMIT_SECONDS=3600\nWEEKEND_LIMIT_SECONDS=7200\nALLOWED_WINDOW_START=06:00\nALLOWED_WINDOW_END=19:00\n' > "$ACUKIDS_HOME/config/timekpr-defaults.conf"
printf 'DNS_V4_PRIMARY=1.1.1.3\nDNS_V4_SECONDARY=1.0.0.3\nDNS_V6_PRIMARY=2606:4700:4700::1113\nDNS_V6_SECONDARY=2606:4700:4700::1003\n' > "$ACUKIDS_HOME/config/dns.conf"
printf '{"admin_account":"administrator"}\n' > "$ACUKIDS_HOME/config/system-meta.json"

# shellcheck source=/dev/null
source "$generated"
validate_config

printf 'sentinel\n' > "$ACUKIDS_HOME/sentinel"
printf 'bad domain\n' >> "$ACUKIDS_HOME/config/whitelist-sites.conf"
if validate_config; then
  echo "invalid configuration was accepted" >&2
  exit 1
fi
[[ "$(cat "$ACUKIDS_HOME/sentinel")" == "sentinel" ]]

printf 'example.com\n' > "$ACUKIDS_HOME/config/whitelist-sites.conf"
printf '[{"id":"example","label":"Example","url":"https://not-allowed.example/"}]\n' > "$ACUKIDS_HOME/config/homepage-links.json"
if validate_config; then
  echo "homepage URL outside browser whitelist was accepted" >&2
  exit 1
fi

printf '[{"id":"example","label":"Example","url":"http://example.com/"}]\n' > "$ACUKIDS_HOME/config/homepage-links.json"
if validate_config; then
  echo "non-HTTPS homepage URL was accepted" >&2
  exit 1
fi

printf '[{"id":"example","label":"Example","url":"https://example.com/"},{"id":"example","label":"Duplicate","url":"https://example.com/2"}]\n' > "$ACUKIDS_HOME/config/homepage-links.json"
if validate_config; then
  echo "duplicate homepage IDs were accepted" >&2
  exit 1
fi

printf '{not-json}\n' > "$ACUKIDS_HOME/config/children.json"
if validate_config; then
  echo "malformed JSON was accepted" >&2
  exit 1
fi
[[ "$(cat "$ACUKIDS_HOME/sentinel")" == "sentinel" ]]

echo "apply validation: OK"
