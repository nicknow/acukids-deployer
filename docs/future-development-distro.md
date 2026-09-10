# acuKids distro development plan

**Status:** Draft for owner review  
**Planning baseline:** September 2026

## 1. Objective

Evolve acuKids from a configuration layer applied to Ubuntu Desktop into an
installable operating-system experience with a purpose-built child session,
an acuKids-owned timekeeper, local parent administration, and eventually a
one-shot installation ISO.

The existing `main` branch remains the supported `0.8-beta` deployer while
this work is exploratory. Abandoning the distro effort must leave that product
usable without a revert or migration.

## 2. Decisions already made

- Ubuntu 26.04 LTS remains the base distribution.
- acuKids will replace timekpr-next. Granular rules—including time charged only
  while a particular application is in focus—are a core product requirement.
- acuKids will ultimately publish its own installable ISO so a parent does not
  need to install Ubuntu and then configure it separately.
- The child interface will be purpose-built; the parent/recovery environment
  may continue to use GNOME.
- The owner remains authoritative. Validation, warnings, history, backups, and
  rollback protect the owner without preventing intentional changes.
- Whole-disk installation is the initial supported installer mode. Dual boot
  and custom partitioning are not initial requirements.
- `main` will be mostly frozen during this effort except for important fixes to
  the supported deployer.

## 3. Delivery and source strategy

### Branches

- `main`: supported script-on-Ubuntu-Desktop product; bug, security, and
  documentation fixes only.
- `next`: integration branch for the distro effort.
- Short-lived feature branches: reviewed into `next`.

Do not merge `main` into `next` on a schedule. Record every relevant `main`
fix in a small porting ledger and deliberately port or reject it on `next`.
This is safer once the implementations no longer have the same structure.

Before substantial work begins, decide whether ISO/package sources remain on
`next` or move into a separate `acukids-os` repository. A separate repository
is preferred once the distro has independent packages, CI, artifacts, and a
security lifecycle. In either case, the current stable raw-script URL must
continue to resolve to `main` until an explicit release decision.

### Artifacts and version identity

Users may always be offered a “latest” download, but every experimental ISO
must be immutable and identifiable by:

- acuKids release name;
- monotonically increasing image build number;
- source commit;
- SHA-256 checksum;
- Ubuntu base version; and
- build/test result.

Git tags are optional. Immutable build identity is not. Moving `next` or
`main` refs must never be the only way to identify an installed image.

### Promotion and rollback

Nothing from this plan becomes the supported product without an explicit owner
decision. Repository promotion, artifact publication, and installed-machine
recovery are separate operations:

- source rollback may use a revert;
- publication rollback repoints “latest” to a previously tested immutable
  artifact; and
- installed systems require a tested update rollback or documented reinstall.

## 4. Target architecture

```text
Ubuntu base
  |
  +-- parent/recovery desktop
  +-- acuKids child compositor session
  |     +-- launcher and child shell
  |     +-- focus/activity reporter
  |     +-- time warnings and lockout UI
  |     `-- constrained application launching
  +-- acuKids control plane
  |     +-- canonical versioned configuration
  |     +-- validation, migration, apply, and rollback
  |     +-- parent API/UI
  |     +-- child homepage service
  |     `-- health and audit records
  +-- acuKids timekeeper daemon
  |     +-- authoritative monotonic ledger
  |     +-- per-child/global/category/app policies
  |     +-- DBus API with polkit authorization
  |     `-- PAM/logind enforcement backstop
  `-- package/image update and recovery mechanism
```

Components should be delivered as installable packages once their interfaces
stabilize. The current deploy script may install prototypes, but it should not
remain the long-term source container for the compositor, daemon, UI, and ISO
builder.

## 5. Phased implementation

### Phase 0 — Establish the development foundation

Purpose: create an isolated, reproducible environment before changing the
product architecture.

Work:

- Create `next` and document the production freeze and bug-porting process.
- Establish package/component boundaries and a versioned configuration schema.
- Define immutable experimental build metadata.
- Create a representative hardware matrix, including low-memory, legacy BIOS,
  older integrated graphics, Broadcom wireless, audio, suspend/resume, and
  touchscreen where available.
- Add CI for host-safe tests and package builds. Schedule expensive VM/ISO
  tests appropriately rather than requiring a full installation on every
  trivial commit.
- Record redistribution, firmware, artwork, font, Ubuntu trademark, and source
  licensing obligations.

Exit criteria:

- `main` behavior and publication are unaffected.
- A clean development machine can reproduce prototype packages.
- Every artifact can be traced to its source commit.

### Phase 1 — Prove the child-session model

Purpose: test the central product idea before investing in ISO engineering.

Work:

- Install Sway and labwc prototypes as optional child sessions alongside GNOME
  on disposable Ubuntu Desktop systems.
- Register sessions through the display manager and select them only for test
  child accounts.
- Provide the minimum session plumbing: polkit agent, notifications, PipeWire,
  volume/brightness keys, idle handling, logout, lockout surface, file chooser,
  and on-screen keyboard assessment.
- Use a hardcoded launcher and current timekpr enforcement solely for session
  feasibility testing.
- Test the oldest target GPU and 4 GB/8 GB systems before choosing a compositor.

Exit criteria:

- One compositor is selected with documented reasons and hardware results.
- Children can launch, use, and exit representative applications reliably.
- Parent GNOME sessions remain unaffected.
- The owner explicitly approves proceeding.

### Phase 2 — Build the child shell and launcher

Purpose: turn the compositor prototype into a supported child experience.

Work:

- Build an icon-first launcher with large touch/mouse targets and recognizable
  application names and icons.
- Add an obvious “I’m all done” action, time-status surface, notifications, and
  a wind-down/lockout experience.
- Launch applications through controlled systemd user scopes so acuKids can
  associate windows and processes with stable application IDs.
- Implement per-child application and presentation policy without depending on
  GNOME app-grid hiding.
- Package the child shell, session definition, configuration, and assets.
- Test keyboard navigation, contrast, scaling, motor accessibility, and
  behavior without reading ability.

Exit criteria:

- The child session is daily-usable on the hardware matrix.
- Application identity is stable enough for timekeeper rules.
- Session crashes fail to a safe login/recovery path rather than a blank screen.

### Phase 3 — Implement the acuKids timekeeper

Purpose: replace timekpr-next with an acuKids-owned policy and accounting
system that supports granular child rules.

Policy model:

- global daily/weekly allowances;
- allowed days and wall-clock windows;
- category allowances, such as games;
- per-application allowances;
- foreground-focus charging rules;
- temporary parent grants or deductions that expire at the intended boundary;
- warning and wind-down thresholds; and
- explicitly defined precedence when several limits apply.

Implementation:

- A root-owned daemon maintains the authoritative ledger and policy state.
- Use monotonic time for usage accrual; use wall clock only for calendar/window
  decisions.
- The compositor/session reports focus changes using stable app IDs. Correlate
  windows with launcher-created scopes rather than relying only on executable
  names.
- Persist accounting frequently and transactionally across suspend, reboot,
  crashes, and power loss.
- Expose a narrow DBus API protected by polkit. Children may read their status;
  only the parent/admin authority may change policy or time.
- Enforce the friendly experience in the child shell and retain a PAM/logind
  backstop for alternate sessions, TTYs, and shell failure.
- Define whether concurrent sessions charge once or cumulatively.
- If wall-clock time is invalid and unavailable from the network, enforce quota
  while degrading the hours window safely and visibly.
- Provide audited parent grants such as “add 20 minutes today” and “remove 20
  minutes today.”
- Migrate current per-child time limits from acuKids/timekpr configuration.

Required tests:

- app focus/background transitions and rapid focus changes;
- general, category, and app limits reaching zero in different orders;
- suspend/resume, reboot, crash, and unclean shutdown;
- DST, timezone changes, clock rollback, invalid RTC, and offline boot;
- concurrent sessions and attempts to bypass through TTY/alternate sessions;
- grant/deduction expiration and ledger corruption recovery.

Exit criteria:

- timekpr-next is no longer required on `next`.
- Accounting error stays within a documented tolerance.
- App-in-focus limits work for representative native, Electron, Java, Wine (if
  supported), and browser applications—or unsupported classes are documented.
- Failure behavior never silently grants unlimited access or permanently locks
  out every child.

### Phase 4 — Consolidate the local control plane and parent UI

Purpose: give non-technical owners one configuration surface backed by the same
validated operations used by the CLI.

Work:

- Define a stable local API over a Unix socket or loopback interface.
- Move child, app, website, homepage, tier, and time policy into versioned
  canonical schemas with idempotent migrations.
- Build an on-device parent UI first. Keep the CLI as a supported recovery
  interface.
- Add preview, confirmation, snapshot, apply, health check, and rollback.
- Serve the child homepage from an unprivileged loopback-only read service.
- Preserve owner app/site/homepage choices when defaults evolve.
- Evaluate phone-based first-boot setup separately. LAN exposure requires
  explicit pairing, authentication, expiry, CSRF protection, and a threat-model
  review; it is not assumed by this phase.

Exit criteria:

- UI and CLI produce the same canonical transactions.
- A broken UI does not prevent local CLI recovery.
- No child-accessible endpoint can modify administrative policy.

### Phase 5 — Build the first acuKids ISO

Purpose: deliver the promised one-shot installation after its components and
dependencies are known.

Work:

- Build an Ubuntu 26.04-based autoinstall ISO containing the proven packages.
- Initially prefer the Ubuntu Desktop base for hardware reliability; moving to
  minimal is a separate measured decision.
- Split image-baked provisioning from first-boot, machine-specific setup.
- Provide a local first-boot wizard plus a TTY fallback.
- Support whole-disk erase with unmistakable confirmation.
- Design the disk layout now for future factory recovery, even if the first
  image does not expose factory reset.
- Include required firmware and test UEFI, legacy BIOS, Secure Boot policy,
  networking, offline failure, and installer interruption.
- Publish immutable experimental ISOs and checksums. A moving “latest” link may
  point to the currently recommended build.

Exit criteria:

- A parent can boot USB media, clearly confirm disk erasure, complete first
  boot, and reach both parent and child sessions.
- Automated QEMU tests verify installation and a machine-readable health marker.
- The full physical hardware set passes installation, networking, graphics,
  audio, input, reboot, and recovery-path checks.

### Phase 6 — Evaluate and, if justified, adopt a minimal base

Purpose: determine whether an additive package base provides enough value to
justify increased hardware and maintenance risk.

Measure Ubuntu Desktop and minimal variants for ISO size, installed size, idle
memory, boot time, package count, hardware support, and parent workflows. Keep
Ubuntu Desktop if the measured gain is modest. If minimal wins, maintain an
explicit package manifest and repeat the full hardware test set.

Treat 4 GB as an experimental minimum until measurements prove it reliable;
8 GB remains the recommended target meanwhile.

### Phase 7 — Updates, factory reset, and release readiness

Purpose: operate the distro safely after installation.

Work:

- Deliver acuKids-owned packages through a verified update channel before
  offering automatic feature updates.
- Keep Ubuntu security updates, acuKids updates, third-party dependencies, and
  reboot policy independently controllable.
- Stage updates, migrate configuration, run health checks, and retain a tested
  rollback target.
- Implement boot-menu factory reset using the storage/recovery design selected
  in Phase 5. Specify exactly whether child data, parent configuration, network
  credentials, and device identity are preserved.
- Evaluate image mode only after package-update failure data exists. It is not
  a prerequisite for the first distro release.
- Define support, security-response, privacy, diagnostics, and artifact
  retention procedures.

Exit criteria:

- Updates and failed-update recovery work on representative older images.
- Factory reset works without external media and communicates data loss clearly.
- Existing script-based acuKids machines have a tested migration or explicit
  reinstall guidance.
- The owner makes an explicit release decision after sustained test results and
  non-team hardware feedback.

## 6. Continuous workstreams

- **Hardware:** maintain results by exact machine/GPU/Wi-Fi configuration.
- **Security:** track Ubuntu, Firefox, compositor, dependency, and acuKids-owned
  component advisories with an owner-defined response target.
- **Testing:** host-safe tests on every change; package tests on pull requests;
  scheduled ISO installation; manual GUI/hardware acceptance for candidates.
- **Privacy:** keep usage accounting local by default and never log child
  browsing content, credentials, or unnecessary activity detail.
- **Recovery:** every new mutable subsystem defines backup, rollback, degraded
  behavior, and an owner-accessible escape hatch.
- **Documentation:** distinguish production deployer instructions from
  experimental distro instructions at all times.

## 7. Explicit non-goals for the initial distro

- ARM support.
- Dual boot or custom partitioning.
- Remote fleet management.
- Always-on LAN administration.
- Cloud-hosted child activity records.
- Non-English localization.
- Expansion beyond the initial young-child audience.
- Image mode without evidence that its complexity solves observed failures.

## 8. Owner decisions required before work begins

- Keep distro sources on `next` or create a separate repository.
- Select the initial hardware validation set.
- Define 4 GB support expectations and the recommended hardware floor.
- Define app/category time-limit precedence and expected accounting tolerance.
- Define factory-reset data-preservation behavior.
- Define security patch response targets.
- Define experimental tester and final release readiness thresholds.

Dates and staffing estimates should be added only after Phase 1 establishes the
chosen session and the real implementation surface.
