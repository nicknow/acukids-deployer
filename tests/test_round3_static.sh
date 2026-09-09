#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/acukids-deploy.sh"
bash -n "$script"
grep -q 'INSTALL_STATE_FILE=' "$script"
grep -q 'write_install_state' "$script"
grep -q 'INSTALL_LOCK_FILE=' "$script"
grep -q 'SCRIPT_BUILD=' "$script"
grep -q 'Script build:' "$script"
grep -q '"script_build":' "$script"
grep -q 'TIMEKPR_PPA=' "$script"
grep -q 'add-apt-repository -y' "$script"
grep -q -- '--settimelimits' "$script"
grep -q -- '--setalloweddays' "$script"
grep -q -- '--setallowedhours' "$script"
grep -q -- '--setlockouttype.*lock' "$script"
grep -q 'start_min=\$((10#\${start##\*:}))' "$script"
grep -q 'end_min=\$((10#\${end##\*:}))' "$script"
if grep -q -- '--setlimits\|--settimelimitsfordays\|LOCKSCREEN' "$script"; then
  echo 'Stale timekpr 0.5.4 CLI syntax remains in the installer.' >&2
  exit 1
fi
grep -q 'sha256sum.*acukids-generated.sha256' "$script"
grep -q 'step_desktop_lockdown' "$script"
grep -q 'prepare_child_user_dirs' "$script"
grep -q 'OverrideFirstRunPage' "$script"
grep -q 'gnome-initial-setup-done' "$script"
grep -q 'acukids-login-logo.svg' "$script"
grep -q 'system-db:gdm' "$script"
grep -q 'ACUKIDS_ASSET_BASE_URL:-https://raw.githubusercontent.com' "$script"
if grep -q 'type == "array" and length > 0 and map(.username) | .\[\]' "$script"; then
  echo 'Existing child reconciliation must not iterate over the jq validation boolean.' >&2
  exit 1
fi
grep -q "picture-uri='file:///usr/share/acukids/branding/acukids-wallpaper.png'" "$script"
grep -q '/org/gnome/desktop/background/picture-uri' "$script"
logo_hash=$(sed -n 's/^ACUKIDS_LOGO_SHA256="\([0-9a-f]*\)"/\1/p' "$script")
wallpaper_hash=$(sed -n 's/^ACUKIDS_WALLPAPER_SHA256="\([0-9a-f]*\)"/\1/p' "$script")
[[ -f "$repo_root/acukids-logo.png" && -f "$repo_root/acukids-wallpaper.png" ]]
[[ "$(sha256sum "$repo_root/acukids-logo.png" | awk '{print $1}')" == "$logo_hash" ]]
[[ "$(sha256sum "$repo_root/acukids-wallpaper.png" | awk '{print $1}')" == "$wallpaper_hash" ]]
grep -q "fallback-logo='%s'" "$script"
[[ ${#logo_hash} -eq 64 && ${#wallpaper_hash} -eq 64 ]]
grep -q -- '--allow-downgrades firefox' "$script"
if grep -q 'apt-cache policy firefox | grep -q' "$script"; then
  echo 'Firefox origin check must be safe with pipefail enabled.' >&2
  exit 1
fi
if grep -q 'apt-get purge -y firefox' "$script"; then
  echo 'Firefox replacement must not be purged after installation.' >&2
  exit 1
fi
candidate_line=$(grep -n 'apt-cache policy firefox' "$script" | head -n1 | cut -d: -f1)
remove_line=$(grep -n 'snap remove firefox' "$script" | head -n1 | cut -d: -f1)
(( remove_line > candidate_line ))
echo 'round-three static checks: OK'

grep -q 'acukids-done.desktop' "$script"
grep -q 'gnome-session-quit --logout' "$script"
grep -q "dock-position='BOTTOM'" "$script"
grep -q 'favorite-apps=\[\$favorites\]' "$script"
grep -q 'show-mounts=false' "$script"
grep -q 'show-home=false' "$script"
grep -q '/org/gnome/shell/favorite-apps' "$script"
grep -q 'locks/02-child-ui-locks' "$script"
grep -q 'org.gnome.Nautilus.desktop|org.gnome.font-viewer.desktop' "$script"
grep -q 'nicknow.net/games' "$script"
grep -q 'spaceplace.nasa.gov' "$script"
grep -q '"nasa.gov"' "$script"
grep -q '"uniteforliteracy.com"' "$script"
grep -q '"nga.gov"' "$script"
grep -q 'phet.colorado.edu' "$script"
grep -q 'noaa.gov' "$script"
grep -q 'Kids Games by Nicknow' "$script"
grep -q 'ipv4_method.*link-local' "$script"
grep -q 'connection_profiles=.*UUID,TYPE' "$script"
grep -q 'CHILD_PINS\[\$idx\]:-' "$script"
grep -q 'Retaining existing PIN for resumed child account' "$script"
grep -q 'ipv6_method.*link-local' "$script"
grep -q 'ipv6_method.*ignore' "$script"
grep -q 'blacklist-apps.conf' "$script"
grep -q 'installer-default-apps.conf' "$script"
grep -q 'sync_managed_app_defaults' "$script"
grep -q 'homepage-links.json' "$script"
grep -q 'blacklist-homepage-links.conf' "$script"
grep -q 'sync_managed_homepage_defaults' "$script"
grep -q 'add-homepage-link' "$script"
grep -q 'remove-homepage-link' "$script"
grep -q 'apply_homepage' "$script"
echo 'child desktop UX checks: OK'
