# Repository maintenance

## Sources of truth

`acukids-deploy.sh` is the executable source and the template source for every
file generated under `/opt/acukids`. The root guides are the established
operator documentation. Update those guides and this `docs/` directory when a
code change alters documented behavior.

### Script build identifier

`acukids-deploy.sh` contains a monotonically increasing integer `SCRIPT_BUILD`.
Increment it by one for every change to the installer, including fixes,
behavior changes, and generated-content changes. Do not reuse a build number.
The installer prints the build at startup and in the configuration summary,
logs it, and records it as `script_build` in `/opt/acukids/config/system-meta.json`.
When reporting an installation issue, include this build number and the
corresponding deployment log.

Do not edit a deployed machine's generated files here as though they were
independent source files. Instead, locate the corresponding heredoc or builder
function in `acukids-deploy.sh`.

## Safe change workflow

1. Read `README.md`, the relevant operator guide, and
   [architecture.md](architecture.md).
2. Find both the initial-deployment implementation and any generated
   apply/manage implementation for the subsystem. Many policies are expressed
   twice so initial deployment and later reconciliation agree.
3. Preserve rerun behavior and distinguish required failures from intentionally
   tolerated optional-package or service failures.
4. Update canonical documentation when behavior or operational commands change.
5. Run the proportional checks below.

When `validate_config()` gains a required configuration file, update every
host-safe test fixture under `tests/` in the same change. Fixtures should
contain the smallest valid representation needed to reach the behavior each
test is intended to exercise.

## Validation

For every shell change, run:

```bash
bash -n acukids-deploy.sh
```

Run ShellCheck when installed:

```bash
shellcheck acukids-deploy.sh
```

Review embedded heredoc delimiters and generated variable expansion carefully;
quoted and unquoted heredocs have different expansion behavior. Static checks
cannot verify apt availability, Firefox policy support, GNOME/dconf behavior,
NetworkManager changes, timekpr-next CLI compatibility, account/login behavior,
or rollback on the target release. Test those changes on a disposable Ubuntu
26.04 Desktop VM or machine before broad deployment.

The deployment is destructive to system configuration and should never be run
on a developer workstation merely as a repository test.

## Timekpr-nExT package source

Ubuntu 26.04/resolute currently ships a broken `timekpr-next` build. The
installer therefore adds the upstream `ppa:mjasnik/ppa` repository and requires
`timekpr-next` version 0.5.10 or newer. It verifies the package origin, launcher
contents, daemon health, and CLI functionality before applying child schedules.
Review a newer PPA release and its CLI compatibility before changing
`TIMEKPR_MIN_VERSION` or the time-limit commands in the installer.

## Agent CLI lifecycle

Claude Code, Codex, and OpenCode are installed from npm at the exact versions
declared near the top of `acukids-deploy.sh`. The installer records the resolved
Node.js and package versions in `config/system-meta.json` and the deployment
log. Updating a tool is an intentional release change: review compatibility,
change the pinned version, test on the disposable VM, and publish a new
acuKids release. Roll back by reinstalling the prior pinned version with npm
and re-running the installer/apply workflow; retain the previous release's
metadata for audit. If a package is withdrawn or no longer supports the target
Node.js/Ubuntu release, remove it from the release only after documenting the
replacement or end-of-life decision.

## Branding asset lifecycle

`acukids-logo.png` and `acukids-wallpaper.png` are installer inputs. Whenever
either file changes, update its SHA-256 constant near the top of
`acukids-deploy.sh` and increment `SCRIPT_BUILD`. The installer first accepts a
matching asset beside the script; otherwise it downloads the named file from
`ACUKIDS_ASSET_BASE_URL`. It never installs an asset that fails verification.
For local HTTP testing, set `ACUKIDS_ASSET_BASE_URL` to the directory serving
the script and assets; a piped shell cannot infer its source URL.

Validate branding on the disposable Ubuntu 26.04 VM. Confirm that both child
light and dark desktop modes use the acuKids wallpaper, the setting cannot be
changed by a child, the homepage displays the logo, and GDM shows the combined
acuKids and Ubuntu mark after a reboot. A failed branding download should be
reported as optional and leave the standard Ubuntu appearance usable.

## Documentation placement

Canonical software facts, architecture, operations, security notes, and
decisions belong in `docs/` or the established root guides. Reusable AI prompts,
standards, and workflows belong in `.ai/` and should link to canonical docs.
Task-local investigation notes belong in `.work/<agent-name>/` and are ignored.
