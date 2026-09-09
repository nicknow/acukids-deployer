# acuKids branding

acuKids uses a shared visual identity on the child desktop, Firefox homepage,
and Ubuntu login screen. Branding is intentionally separate from the security
controls: an asset failure is reported, but it does not prevent the locked-down
system from being deployed.

## Source assets

- `acukids-logo.png` is the reusable transparent logo.
- `acukids-wallpaper.png` is the child desktop wallpaper derived from that
  logo. Its subject is centered so GNOME's `zoom` behavior remains usable on
  common 16:9, 16:10, 4:3, and 5:4 displays.

The installer contains a SHA-256 value for each asset. It accepts a matching
file beside `acukids-deploy.sh` or downloads the file from
`ACUKIDS_ASSET_BASE_URL`; an unverified file is never installed.

When the installer is piped from a local HTTP server, pass that server as the
asset base because a piped shell cannot determine the URL that supplied it:

```bash
curl -fsSL http://192.168.88.133:8000/acukids-deploy.sh | \
  sudo env ACUKIDS_ASSET_BASE_URL=http://192.168.88.133:8000 bash
```

## Deployed locations

Verified assets are installed read-only under
`/usr/share/acukids/branding/` and copied into `/opt/acukids/branding/` for the
local control repository. The homepage receives its own logo copy so it works
from its existing `file://` origin.

The child dconf profile sets both the light and dark background URI to the
acuKids wallpaper, uses GNOME's `zoom` mode, and locks those keys. Parent and
fallback accounts retain their own wallpaper preferences.

## Login screen

GDM provides one supported greeter-logo setting, while Ubuntu already uses it
for distribution branding. acuKids therefore generates one SVG lockup that
contains the acuKids logo and a copy of Ubuntu's installed logo, then assigns
that image to both GDM's normal and fallback logo keys. This keeps both brands
visible without modifying GNOME Shell CSS or replacing Ubuntu theme files.

## VM acceptance checks

After running script build 12 or newer and rebooting the disposable Ubuntu
26.04 VM, confirm:

1. GDM shows both the acuKids and Ubuntu marks above the user list.
2. Both child accounts show the acuKids wallpaper after login.
3. Switching GNOME between light and dark appearance does not remove it.
4. A child cannot replace the managed wallpaper through Settings.
5. The Firefox homepage shows the acuKids logo and all site tiles still work.
6. Parent and fallback account wallpapers remain independently configurable.

Useful state checks:

```bash
sudo DCONF_PROFILE=acukids-child dconf read /org/gnome/desktop/background/picture-uri
sudo DCONF_PROFILE=acukids-child dconf read /org/gnome/desktop/background/picture-uri-dark
sudo DCONF_PROFILE=acukids-child dconf read /org/gnome/desktop/background/picture-options
sudo DCONF_PROFILE=gdm dconf read /org/gnome/login-screen/logo
sha256sum /usr/share/acukids/branding/acukids-logo.png \
  /usr/share/acukids/branding/acukids-wallpaper.png
```

Visual confirmation is required for GDM because static tests can verify its
dconf source and image files but cannot prove how the installed GNOME Shell
version renders the composite SVG.
