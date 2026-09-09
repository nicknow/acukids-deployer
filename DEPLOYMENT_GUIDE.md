# acuKids Deployment Guide

This guide walks you through turning a bare-metal PC into a safe, educational
"acuKids" computer for children ages 3-7, running Ubuntu 26.04 LTS ("Resolute Raccoon") with
Edubuntu packages.

---

## 1. What this deployment gives you

| Feature | Behavior |
|---|---|
| OS | Ubuntu 26.04 LTS ("Resolute Raccoon") Desktop |
| Admin account | New dedicated account you create during setup, full sudo |
| Original installer account | Kept as a fallback login, auto-login disabled, not used day-to-day |
| Child accounts | As many as you want, each with a 4-digit PIN login |
| Educational software | GCompris, TuxPaint, TuxMath, TuxType, Krita, Audacity, Stellarium |
| Web filtering | Cloudflare for Families DNS (blocks malware + adult content) |
| Browser (children) | Firefox (.deb), locked to a strict whitelist of approved educational sites |
| Browser (admin) | Chromium (snap), unrestricted, for the admin's own use |
| App menu (children) | Locked down to only the approved educational/creative apps |
| Branding | acuKids child wallpaper, homepage logo, and acuKids + Ubuntu login-screen branding |
| Screen time | 1 hour/day weekdays, 2 hours/day weekends, allowed window 6:00 AM-7:00 PM |
| Updates | Automatic security patches, auto-reboot overnight if needed |
| Ongoing configuration | Managed through `/opt/acukids/`, editable by hand or by an AI coding agent (Claude Code, Codex, OpenCode - all pre-installed) |

---

## 2. Requirements

- A PC that meets [Ubuntu 26.04 Desktop's system requirements](https://ubuntu.com/download/desktop) (6GB+ RAM, 25GB+ disk recommended - 26.04 raised the minimum RAM from 4GB to 6GB)
- Note: 26.04 ships GNOME 50 and is Wayland-only (the GNOME-on-X11 session has been removed). This deployment doesn't rely on X11-specific features, but it's worth knowing if you're used to older Ubuntu releases.
- A USB flash drive (8GB+) for the Ubuntu installer
- An active internet connection on the target machine (wired is more reliable for setup)
- About 45-60 minutes of total time (most of it unattended)

---

## 3. Step 1 - Install plain Ubuntu 26.04 LTS Desktop

This deployment **converts an existing Ubuntu installation** rather than
using a custom ISO, so start with a completely standard install:

1. Download Ubuntu 26.04 LTS ("Resolute Raccoon") Desktop from [ubuntu.com/download/desktop](https://ubuntu.com/download/desktop).
2. Create a bootable USB using [Rufus](https://rufus.ie/) (Windows) or
   [balenaEtcher](https://etcher.balena.io/) (Windows/Mac/Linux).
3. Boot the target PC from the USB and run through the standard Ubuntu
   installer:
   - Choose **"Normal installation"**.
   - You may accept the default option to install updates/third-party
     software during install; it's not required.
   - Erase disk and install Ubuntu (or use whatever disk layout you prefer).
   - When prompted for "Your name" / computer name / username / password,
     these can be anything - this account becomes the **fallback login**
     that the acuKids script keeps but no longer uses for day-to-day login.
   - Complete the install and reboot into the fresh Ubuntu desktop.
4. Log in once, connect to Wi-Fi/Ethernet, and confirm you have internet
   access (open Firefox and load any webpage).

You now have a stock Ubuntu 26.04 Desktop. Everything from here is handled
by the acuKids script.

---

## 4. Step 2 - Run the acuKids deployment script

You have two options to get the script onto the machine:

**Option A - USB drive (fully offline-capable after copy):**
1. Copy `acukids-deploy.sh` onto a USB drive.
2. Plug it into the target PC and copy the file to the Desktop or home folder.
3. Open a terminal (Activities → Terminal) and run:
   ```bash
   cd ~/Desktop
   sudo bash acukids-deploy.sh
   ```

**Option B - One-line install (pulls the latest stable script from GitHub):**
```bash
curl -fsSL https://raw.githubusercontent.com/nicknow/acukids-deployer/main/acukids-deploy.sh | sudo bash
```
If you're hosting your own copy of the script instead (e.g. for a staged
rollout), substitute your host's URL in place of the GitHub one above.

> Either method runs the same installation. When the logo and wallpaper are
> not beside the downloaded script, it retrieves checksum-verified copies from
> the acuKids project repository. A branding download failure is reported but
> does not prevent the safety-related configuration from completing.

---

## 5. Step 3 - Answer the setup questions (all upfront, no more prompts after)

When you run the script, it will ask you the following, **in this order**,
and then run the entire installation unattended:

1. **Computer name / hostname** - press Enter to accept the default `acukids`, or type your own.
2. **Whether to hide the original installer account from the login screen** - it's always kept as a recovery login either way; this only controls whether it shows up in the clickable user list.
3. **Admin username, full name, and password** - this becomes your day-to-day management account.
4. **Number of child accounts** - how many children will use this computer.
5. **For each child**: a username, and a 4-digit PIN (entered twice to confirm).
6. **Final confirmation screen** - review everything, type `y` to proceed.

After you confirm, the script runs completely unattended for roughly
15-30 minutes depending on your internet speed. It will:

- Update the system and install base tools
- Create your admin and child accounts
- Install all educational software
- Replace snap Firefox with a locked-down .deb Firefox for kids, and set up
  Chromium for the admin
- Configure Cloudflare for Families DNS filtering
- Set daily time limits per child
- Lock down the desktop and app menu for child accounts
- Install the acuKids child wallpaper and combined acuKids/Ubuntu login logo
- Enable automatic security updates
- Install Claude Code, Codex CLI, and OpenCode for the admin account
- Build the `/opt/acukids` control repository
- Prompt you once more, at the very end, asking whether to reboot now

**Reboot when prompted** to finalize everything.

> **Re-running the script on an already-deployed machine?** It's safe to
> re-run (it skips creating accounts/config that already exist), and as of
> this version it correctly cleans up any previously-hidden apps when it
> re-applies the desktop lockdown. If you're troubleshooting a stale issue
> from a much older version of this script, running
> `sudo /opt/acukids/scripts/acukids-apply.sh` directly afterward will force
> a full reconciliation of every child account against the current
> whitelist - see the Troubleshooting section below.

---

## 6. Step 4 - First login after reboot

You'll see the Ubuntu login (GDM) screen with a list of user avatars:

- Click the **admin account** and enter its password to manage the system.
- Click a **child's name** and enter their 4-digit PIN to start using
  educational software. (Ubuntu shows a normal password field for this -
  there's no dedicated numeric PIN pad, but a 4-digit code works fine.)
- The original installer account is still present at the bottom of the
  list if you ever need a recovery login, but it no longer auto-logs in.

On first login to a child account, you should see:
- A simplified desktop with only educational/creative apps in the app grid
- Firefox opening to the acuKids homepage with tiles for the currently
  configured educational websites and games
- A time-limit popup/tray icon from timekpr-next showing remaining time

---

## 7. Managing the system day to day

All ongoing management happens through `/opt/acukids/`. Log in as the
**admin account** and open a terminal.

### Quick management commands

```bash
# Add a new child
sudo /opt/acukids/scripts/acukids-manage.sh add-child <username> <4digitpin>

# Remove a child (keeps their files, just removes login/config)
sudo /opt/acukids/scripts/acukids-manage.sh remove-child <username>

# List configured children and their limits
/opt/acukids/scripts/acukids-manage.sh list-children

# Reset a child's time budget today to the configured daily allowance
sudo /opt/acukids/scripts/acukids-manage.sh reset-time <username>

# Change a child's PIN
sudo /opt/acukids/scripts/acukids-manage.sh set-pin <username> <new4digitpin>

# Allow a new website for kids
sudo /opt/acukids/scripts/acukids-manage.sh add-site example.com

# Add a tile for an already-allowed website
sudo /opt/acukids/scripts/acukids-manage.sh add-homepage-link example "Example" "https://example.com/"

# Remove a tile and prevent it returning as an installer default
sudo /opt/acukids/scripts/acukids-manage.sh remove-homepage-link example

# Allow a new app to show in the kids' app grid
sudo /opt/acukids/scripts/acukids-manage.sh add-app someapp.desktop
```

### Editing configuration directly

Everything the manage script does is really just editing files under
`/opt/acukids/config/` and then running:

```bash
sudo /opt/acukids/scripts/acukids-apply.sh
```

This is also how an AI coding agent (see Section 8) makes changes.
Homepage tiles live in `config/homepage-links.json`; their URLs must also be
covered by `config/whitelist-sites.conf`. Installer defaults are additive and
owner removals are recorded in `blacklist-homepage-links.conf`. A manually
customized homepage is preserved by apply.

### Rolling back a bad change

Every time you (or an agent) run `acukids-apply.sh`, the previous
configuration is snapshotted. To undo the most recent change:

```bash
sudo /opt/acukids/scripts/acukids-apply.sh --rollback
```

### Change history

Every deployment action and applied change is logged in:

```
/opt/acukids/CHANGELOG.md
```

The repo is also a local git repository (`/opt/acukids/.git`), so you can
review history with `git -C /opt/acukids log` or `git -C /opt/acukids diff`.

---

## 8. Using an AI coding agent to reconfigure the system

Claude Code, Codex CLI, and OpenCode are pre-installed on the admin
account. Any of these can be pointed at `/opt/acukids/` to inspect and
safely modify the configuration - the directory includes an `AGENTS.md`
(also available as `CLAUDE.md`) that explains the whole system, file
layout, and safe-change rules to the agent automatically.

Example, using Claude Code:

```bash
cd /opt/acukids
claude
```

Then just describe what you want, e.g.:

> "Add a new child account for Emma with PIN 4821, and add
> starfall.com/kindergarten to the whitelist."

The agent will read `AGENTS.md`, make the edits to `config/`, run
`acukids-apply.sh`, and record the change in `CHANGELOG.md` for you.

The same works with `codex` or `opencode` in place of `claude` above.

---

## 9. Troubleshooting

**"Invalid username" (or similar) error appears immediately, before you've typed anything**
This means stdin wasn't connected to your keyboard when the script started
- most commonly because it was run as `curl ... | sudo bash` and the pipe
"ate" the input meant for the prompts. The script now automatically
detects this and reattaches to `/dev/tty`, so simply re-running it should
work. If it still happens, download the script first and run it directly
instead of piping it:
```bash
curl -fsSL <url> -o acukids-deploy.sh
sudo bash acukids-deploy.sh
```

**An app you expect to see is missing from a child's desktop**
This deployment discovers each app's real `.desktop` filename automatically
at install time (via `dpkg -L <package>`) rather than guessing, since some
packages ship names that don't match what you'd expect (Krita's is
`org.kde.krita.desktop`, not `krita.desktop`, for example). If something
you installed later isn't showing up, find its real filename with:
```bash
dpkg -L <package-name> | grep '\.desktop$'
```
Add the exact basename to `/opt/acukids/config/whitelist-apps.conf` and
re-apply:
```bash
sudo /opt/acukids/scripts/acukids-apply.sh
```

**I fixed the whitelist / re-ran the deploy script, but the app is still hidden**
If an app was ever wrongly hidden in the past (for example, from an older
version of this script that guessed a `.desktop` filename incorrectly),
a per-account "hide" file was written into that child's
`~/.local/share/applications/`. Simply correcting the whitelist and
re-running the deploy script does **not** by itself remove that old file -
the deploy script only writes new hide-files, it doesn't invoke the apply
step at the end. Run the apply script directly to force a full
regeneration (it clears old overrides before rebuilding them):
```bash
sudo /opt/acukids/scripts/acukids-apply.sh
```
If you're not sure whether a stale override exists, you can check directly:
```bash
ls ~<child-username>/.local/share/applications/
```
Any file there with `NoDisplay=true` is hiding that app for that child
specifically, regardless of what the system-wide app does.

**The original installer account shows on the login screen and I don't want it to**
This is expected if you chose not to hide it during setup (or if you're
running an older version of the script from before this option existed).
The account itself is never deleted regardless - only its visibility in
the clickable login list changes. To hide it now:
```bash
sudo /opt/acukids/scripts/acukids-manage.sh hide-fallback-account <original-username>
```
It will still work as a login if you type the username manually; this
only removes it from the picker. To reverse it: `show-fallback-account`
instead of `hide-fallback-account`.

**A child's PIN doesn't work / they're locked out for the day**
Check their time budget: `timekpra --userinfo <username>`. If they've hit
the daily limit, either wait until the next allowed window or run
`reset-time` as shown above.

**Firefox reverted to opening the Ubuntu Software Store / snap version**
Check `/etc/apt/preferences.d/mozilla-firefox` is still present and run
`sudo /opt/acukids/scripts/acukids-apply.sh`. This pin file is what stops
Ubuntu's snap-based Firefox from reappearing after updates.

**A website that should be allowed is blocked**
Confirm the domain is listed (no `http://`, no trailing slash) in
`/opt/acukids/config/whitelist-sites.conf`, then re-run
`sudo /opt/acukids/scripts/acukids-apply.sh`.

**Firefox blocks its own homepage when a child opens the browser**
This is fixed as of the current version of the deploy/apply scripts - the
browser whitelist policy blocks every URL scheme by default (including
`file://`, not just websites), and the local homepage needs its own
explicit exception. If you're seeing this on an already-deployed machine,
run:
```bash
sudo /opt/acukids/scripts/acukids-apply.sh
```
to regenerate `/etc/firefox/policies/policies.json` with the fix included.
If you ever add another local `file://` page for children to use, it will
need the same kind of exception - see `AGENTS.md`'s browser-split section
for where to add it.

**Need to log in as the original installer account**
It's still on the login screen. Its password is whatever was set during
the original Ubuntu installation in Section 3.

**Full deployment log**
Everything the deploy script did is recorded in `/var/log/acukids-deploy.log`.

---

## 10. Security notes

- Child accounts have no sudo access and the normal desktop hides terminal,
  software-installation, and system-settings entry points. This is intended to
  prevent routine or casual access; it is not a defense against a technically
  capable local user with physical access (see
  [the threat model](docs/threat-model.md)).
- DNS filtering (Cloudflare for Families) provides network-level defense in
  depth, and the Firefox whitelist restricts child browsing to approved sites.
  These are not absolute protections against custom resolvers, encrypted DNS,
  proxies, VPNs, or literal IP access.
- The admin account's Chromium browser is intentionally unrestricted -
  keep the admin password private and don't share it with children.
- Automatic security updates are enabled; the machine may reboot on its
  own around 3:30 AM if updates require it and no one is logged in.
