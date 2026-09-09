#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export ACUKIDS_LIBRARY_MODE=true
# shellcheck source=../acukids-deploy.sh
source "$repo_root/acukids-deploy.sh"

BRANDING_DIR="$work/branding"
LOG_FILE="$work/deploy.log"
install_branding_assets

asset_has_expected_hash "$BRANDING_DIR/acukids-logo.png" "$ACUKIDS_LOGO_SHA256"
asset_has_expected_hash "$BRANDING_DIR/acukids-wallpaper.png" "$ACUKIDS_WALLPAPER_SHA256"
grep -q 'data:image/png;base64,' "$BRANDING_DIR/acukids-login-logo.svg"
grep -q 'data:image/svg+xml;base64,' "$BRANDING_DIR/acukids-login-logo.svg"
if command -v gtk4-image-tool >/dev/null 2>&1; then
  gtk4-image-tool info "$BRANDING_DIR/acukids-login-logo.svg" >/dev/null
fi

echo 'branding assets: OK'
