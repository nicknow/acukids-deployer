#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

export ACUKIDS_LIBRARY_MODE=true
export ACUKIDS_HOME="$test_root/acukids"
# shellcheck source=/dev/null
source "$repo_root/acukids-deploy.sh"

mkdir -p "$ACUKIDS_HOME"/config "$ACUKIDS_HOME"/homepage
CHILD_USERNAMES=(alice)
WHITELIST_APPS_RUNTIME=(example.desktop)
ACUKIDS_HOSTNAME=acukids-test
ORIGINAL_ADMIN_USER=fallback
HIDE_ORIGINAL_ACCOUNT=true
ADMIN_USERNAME=administrator

# Generate a fresh control repository subset.
build_children_json
build_whitelist_sites_conf
build_whitelist_apps_conf
build_timekpr_conf
build_dns_conf
build_system_meta_json
build_homepage
build_changelog

# Simulate administrator customizations made after deployment.
printf '[{"username":"custom-child","weekday_limit_seconds":900}]\n' > "$ACUKIDS_HOME/config/children.json"
printf '# custom site\nexample.test\n' > "$ACUKIDS_HOME/config/whitelist-sites.conf"
printf '# custom app\ncustom.desktop\n' > "$ACUKIDS_HOME/config/whitelist-apps.conf"
printf 'WEEKDAY_LIMIT_SECONDS=900\n' > "$ACUKIDS_HOME/config/timekpr-defaults.conf"
printf 'DNS_V4_PRIMARY=192.0.2.1\n' > "$ACUKIDS_HOME/config/dns.conf"
printf '{"custom":true}\n' > "$ACUKIDS_HOME/config/system-meta.json"
printf '<html>custom homepage</html>\n' > "$ACUKIDS_HOME/homepage/index.html"
printf '# existing changelog\n' > "$ACUKIDS_HOME/CHANGELOG.md"

before=$(find "$ACUKIDS_HOME/config" "$ACUKIDS_HOME/homepage" -type f -print0 | sort -z | xargs -0 sha256sum)
build_children_json
build_whitelist_sites_conf
build_whitelist_apps_conf
build_timekpr_conf
build_dns_conf
build_system_meta_json
build_homepage
build_changelog
after=$(find "$ACUKIDS_HOME/config" "$ACUKIDS_HOME/homepage" -type f -print0 | sort -z | xargs -0 sha256sum)

[[ "$before" == "$after" ]] || {
  echo "rerun preservation failed: canonical files changed" >&2
  exit 1
}
grep -q 'Reconciled existing acuKids deployment' "$ACUKIDS_HOME/CHANGELOG.md"

echo "rerun preservation: OK"
