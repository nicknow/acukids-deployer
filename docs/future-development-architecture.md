# Future development architecture

This document records the intended direction for acuKids as features expand.
It is a planning document, not a commitment to implement every component
immediately. The current product remains a single URL-invoked installer that
creates a local `/opt/acukids` control repository.

## Guiding principles

- Keep the human installation experience as one simple command.
- Treat the computer owner as authoritative. The system may validate, preview,
  snapshot, and roll back changes, but must not silently override owner intent.
- Keep canonical configuration separate from generated operating-system state.
- Make every mutation observable, versioned, and recoverable.
- Prefer a small number of well-defined local services over a larger distributed
  management system.
- Preserve a usable degraded mode when optional components fail, while refusing
  to claim success for required protections.

## Target shape

The installer should gradually become a bootstrapper for a versioned local
control plane:

```text
Stable install URL
        |
        v
Bootstrap installer
        |
        v
/opt/acukids control plane
  |-- canonical configuration and schemas
  |-- validation, migrations, apply, and rollback
  |-- local parent API and web UI
  |-- child homepage service
  |-- update manager
  `-- health checks and audit history
```

The installer remains self-contained for distribution. The current generated
control repository already supports local Git history, snapshots/rollback,
owner-managed app and homepage blacklists, and a CLI apply/manage boundary.
Internal source files and a deterministic build process may be introduced
later, provided the published artifact and user command remain simple.

## Control plane

Keep `/opt/acukids` as the deployed source of truth:

- `config/` contains owner-controlled policy.
- `schema/` may contain schema versions and idempotent migrations as the
  configuration model grows (the current deployment keeps schema metadata in
  `config/system-meta.json`).
- `state/` contains snapshots, last-applied state, update state, and recovery
  copies.
- `bin/` or `scripts/` contains narrow, auditable operations.
- `ui/` contains local web assets.
- `service/` contains systemd units and service configuration.
- `CHANGELOG.md` records operational changes.

Each subsystem should define its configuration, validation, apply operation,
health check, rollback behavior, and required/optional failure policy.

## Parent web UI and API

Add a local-only parent service. Prefer a Unix socket or loopback binding over
LAN exposure. The service should:

- authorize only the acuKids administrator/owner group;
- use OS authentication or a narrowly scoped privileged helper;
- expose no child-accessible administrative endpoint;
- validate and preview changes before confirmation;
- write canonical configuration and invoke one apply engine;
- protect browser sessions against CSRF and stale requests; and
- never log passwords, PINs, or tokens.

The UI must not independently edit `/etc`, accounts, Firefox policy, dconf,
DNS, or timekeeping state. Its boundary is:

```text
Parent UI -> local API -> validated configuration transaction -> apply engine
```

The existing shell apply engine can serve as the first backend, but its
interface should become explicit and structured before the UI grows.

## Local child homepage

The current homepage is a generated `file://` page with owner-managed links.
If file-URL startup behavior or richer local experiences become important,
replace it with a small read-only HTTP service bound only to loopback. It
should run unprivileged, start before graphical child sessions, and serve
generated content from the control repository. Firefox policy must allow only
the fixed local origin and the configured external sites.

This removes file-URL startup quirks and provides a stable foundation for
approved resources, local status, and future parent/child experiences without
making the homepage an administrative API.

## Updates

Future acuKids software updates should be owner-controlled by default and
staged before activation. This is separate from the current Ubuntu unattended
security-upgrade policy and the manual URL-based installer rerun:

1. Discover a signed release manifest.
2. Verify the artifact, version, and compatibility.
3. Snapshot configuration and runtime state.
4. Stage and validate the update and its migrations.
5. Apply it transactionally.
6. Run subsystem health checks.
7. Reboot only when required and authorized.
8. Roll back automatically if startup or health checks fail.

Provide separate policies for Ubuntu security updates, acuKids updates,
third-party dependencies, and reboot behavior. Automatic updates may be added
later, but they must never silently discard owner edits or bypass rollback.

## Versioning and compatibility

Track these independently:

- installer `SCRIPT_BUILD`;
- control-plane release;
- configuration schema;
- generated artifact version; and
- component versions and package origins.

Every schema or live-system change needs an idempotent migration, a backup, a
clear log entry, and tests against at least one older deployed state. Dependency
changes such as Firefox or timekpr updates require VM validation before release.

## Implementation phases

The detailed phased roadmap is maintained in
[future-development-distro.md](future-development-distro.md). It prototypes the
child session before ISO engineering, commits to an acuKids-owned timekeeper,
then adds the parent control plane and one-shot ISO after component boundaries
and hardware requirements are known.

## Non-goals for the near term

- Remote fleet management.
- LAN-exposed administration.
- Replacing the owner’s judgment with automated policy decisions.
- Splitting the published installer into multiple downloads.
- GUI automation as a substitute for system-state and manual VM acceptance.
