# Architecture

## Purpose and scope

acuKids converts a stock Ubuntu 26.04 LTS Desktop installation into a managed
educational computer for children ages 3–7. The repository intentionally has
one executable source file, `acukids-deploy.sh`. It gathers all installation
answers first, applies the machine configuration, and creates a separate local
control repository at `/opt/acukids` for ongoing administration.

The installer is designed for an interactive, root-run, network-connected
Ubuntu machine. It uses `set -uo pipefail`, but deliberately does not use
`set -e`: selected package and service failures are logged and tolerated so an
optional component does not necessarily abort the deployment. Fatal
prerequisites use the script's `die` helper.

## Deployment lifecycle

The main function performs these phases in order:

1. Verify root access, target Ubuntu release, minimum memory, internet access,
   and interactive input availability.
2. Gather and confirm the hostname, fallback-account visibility, administrator
   credentials, and child accounts. Passwords and PINs are held in memory and
   unset after account creation.
3. Update Ubuntu and install base and educational packages. Educational package
   failures are retried individually and may be skipped with a log entry.
4. Configure accounts, browsers, filtered DNS, time limits, GNOME lockdown,
   application visibility, and unattended security updates.
5. Install the supported AI coding command-line tools for the administrator.
6. Generate `/opt/acukids`, initialize it as its own Git repository, and install
   its apply and management commands.
7. Offer to reboot after finalization.

Deployment activity is written to `/var/log/acukids-deploy.log`.

## Security and policy boundaries

- The original Ubuntu installer account remains as a recovery path. It may be
  hidden from GDM but is not removed.
- A dedicated administrator account receives sudo access and membership in the
  generated `acukids-admin` group. The generated sudoers entry permits only the
  acuKids apply and management commands without a password.
- Child accounts share the `acukids-children` group, have no sudo access, use a
  four-digit Linux password as a PIN, and receive a dedicated dconf profile.
- Cloudflare for Families resolvers are configured in systemd-resolved and on
  NetworkManager connections with automatic DNS ignored. This is defense in
  depth, not an absolute egress boundary against DoH, custom resolvers,
  proxies, VPNs, or literal IPs.
- Firefox is installed from Mozilla's APT repository and receives machine-wide
  enterprise policies. Its `WebsiteFilter` blocks all URLs except configured
  domains and the local homepage. Chromium remains unrestricted for the
  administrator because Firefox policy is machine-wide.
- Non-whitelisted desktop applications are hidden per child through
  `NoDisplay=true` overrides. Installed educational packages are inspected with
  `dpkg -L` so the real `.desktop` filenames are used.
- timekpr-next applies weekday/weekend budgets and a daily allowed window.
- Unattended security upgrades may reboot the machine at 03:30 when no user is
  logged in.

These controls are defense in depth, not a claim that short PINs or local
desktop policy provide strong security against a technically capable attacker.

## Generated control repository

`/opt/acukids` is runtime output, not a checked-in subtree of this repository.
The deployment script generates:

| Area | Role |
|---|---|
| `config/` | Canonical deployed-machine configuration for children, sites, apps, time limits, DNS, and metadata |
| `scripts/acukids-apply.sh` | Snapshots configuration and reconciles it to live system files and services; supports rollback |
| `scripts/acukids-manage.sh` | Provides common account, PIN, time, site, app, homepage-link, and fallback-account operations |
| `homepage/` | Local Firefox start page for child accounts |
| `branding/` | Verified acuKids logo and child wallpaper assets |
| `state/` | Timestamped rollback snapshots |
| `AGENTS.md` and `CLAUDE.md` | Generated instructions for tools operating on the deployed machine |
| `CHANGELOG.md` | Append-only operational change log |

On a deployed machine, files under `/opt/acukids/config` are the source of
truth. The apply script regenerates live configuration; administrators and
agents should not edit derived files under `/etc` or child home directories.

## Important implementation details

- The installer logic and generated shell, JSON, HTML, configuration, and agent
  documentation are contained in `acukids-deploy.sh`. The logo and wallpaper
  are separate repository assets: the installer prefers matching files beside
  the script and otherwise downloads them from the project repository. Both
  files are checked against hashes embedded in the installer before use.
- Branding failure is optional and does not block safety-critical deployment.
  When available, the wallpaper is mandatory for child profiles and the GDM
  logo is a composite that retains Ubuntu branding alongside acuKids.
- Reapplying application lockdown first removes existing per-child desktop
  overrides, then rebuilds them. This prevents stale hides when a whitelist
  entry changes.
- The Firefox allowlist must always include
  `file:///opt/acukids/homepage/*`; `<all_urls>` blocks `file://` URLs too.
- The apply script snapshots its current canonical configuration before
  applying. Rollback restores the latest snapshot and then applies it.
- The initial deployment and the generated control repository each have their
  own Git history. They are separate repositories with different purposes.
