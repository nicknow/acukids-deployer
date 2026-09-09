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
mkdir -p "$ACUKIDS_HOME/config" "$ACUKIDS_HOME/state"
mkdir -p "$test_root/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/nmcli"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/resolvectl"
chmod +x "$test_root/bin/nmcli" "$test_root/bin/resolvectl"
export PATH="$test_root/bin:$PATH"
printf '# test changelog\n' > "$ACUKIDS_HOME/CHANGELOG.md"
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
require_root() { :; }
apply_accounts() { :; }
apply_admin_account() { :; }
apply_dconf_profiles() { :; }
apply_dns() { :; }
apply_firefox_whitelist() { :; }
apply_app_whitelist() { :; }
apply_homepage() { :; }
apply_time_limits() { :; }
dconf() { :; }

for failed_step in accounts admin dconf_profiles dns firefox applications time_limits dconf; do
  case "$failed_step" in
    accounts)       apply_accounts() { return 1; } ;;
    admin)          apply_admin_account() { return 1; } ;;
    dconf_profiles) apply_dconf_profiles() { return 1; } ;;
    dns)            apply_dns() { return 1; } ;;
    firefox)        apply_firefox_whitelist() { return 1; } ;;
    applications)  apply_app_whitelist() { return 1; } ;;
    time_limits)    apply_time_limits() { return 1; } ;;
    dconf)          dconf() { return 1; } ;;
  esac

  if apply_all; then
    echo "failure reporting failed for $failed_step" >&2
    exit 1
  fi
  grep -q "FAILED to apply configuration (subsystems:.*$failed_step" "$ACUKIDS_HOME/CHANGELOG.md"

  case "$failed_step" in
    accounts)       apply_accounts() { :; } ;;
    admin)          apply_admin_account() { :; } ;;
    dconf_profiles) apply_dconf_profiles() { :; } ;;
    dns)            apply_dns() { :; } ;;
    firefox)        apply_firefox_whitelist() { :; } ;;
    applications)  apply_app_whitelist() { :; } ;;
    time_limits)    apply_time_limits() { :; } ;;
    dconf)          dconf() { :; } ;;
  esac
done

echo "apply failure reporting: OK"
