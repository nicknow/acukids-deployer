#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Extract generated scripts without sourcing or running the installer. This is
# deliberately host-safe: no root, package manager, service, account, or
# system-path operation is possible.
awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-apply.sh"/ { found=1; next }
     found && /^APPLY_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$tmp/acukids-apply.sh"
awk '/cat > "\$ACUKIDS_HOME\/scripts\/acukids-manage.sh"/ { found=1; next }
     found && /^MANAGE_SCRIPT_EOF$/ { exit }
     found { print }' "$repo_root/acukids-deploy.sh" > "$tmp/acukids-manage.sh"

bash -n "$repo_root/acukids-deploy.sh" "$tmp/acukids-apply.sh" "$tmp/acukids-manage.sh"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$repo_root/acukids-deploy.sh" "$tmp/acukids-apply.sh" "$tmp/acukids-manage.sh"
fi

[[ -s "$tmp/acukids-apply.sh" && -s "$tmp/acukids-manage.sh" ]]
grep -q '"WebsiteFilter"' "$tmp/acukids-apply.sh"
grep -q 'file:///opt/acukids/homepage' "$tmp/acukids-apply.sh"
grep -q 'flock' "$tmp/acukids-apply.sh"
grep -q 'INSTALL_LOCK_FILE' "$repo_root/acukids-deploy.sh"
! grep -q 'rm -rf /' "$tmp/acukids-apply.sh" "$tmp/acukids-manage.sh"
echo "host-safe extraction and syntax checks: OK"
