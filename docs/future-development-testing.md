# Potential future development: isolated system testing

This plan describes testing beyond the current host-safe static, generated-
artifact, locking, validation, rollback, and management-command tests. It is a
future enhancement, not part of the current implementation scope.

The objective is to test destructive operating-system configuration without
applying acuKids to a developer's current OS. Work proceeds through disposable
environments, culminating in a real Ubuntu Desktop virtual machine.

## Constraints

- Never execute the production installer against a developer workstation.
- Keep the human installation experience available as one simple command
  against a URL.
- Treat containers as partial integration environments, not evidence that GUI,
  login, networking, snap, or session controls work.
- Reset test environments to a known snapshot between scenarios.
- Do not place test credentials in source, command output, or persistent logs.

## 1. Mocked command tests

Place controlled fake system commands earlier in `PATH` during a test. Useful
fakes include:

```text
apt-get
snap
systemctl
nmcli
timekpra
adduser
deluser
usermod
chpasswd
hostnamectl
reboot
```

Each fake should record structured arguments and return a result selected by
the test. The test harness can then verify orchestration without changing an
account, service, package, hostname, network, or boot state.

Candidate scenarios:

- Required-command failure returns nonzero and suppresses success output.
- Optional educational-package failure produces the expected degraded result.
- Passwords and PINs never appear in captured commands or logs beyond the
  protected input channel required by the receiving command.
- Existing account adoption and collision rules behave as designed.
- NetworkManager identifiers containing spaces or special characters remain
  single arguments.
- Rerun, migration, apply, and rollback operations occur in the intended order.
- Reboot is requested only after a successful deployment and explicit choice.

This layer may require small dependency-injection seams for command lookup and
filesystem roots. Production defaults must remain the real commands and real
root filesystem.

## 2. Disposable container integration tests

Use a disposable Ubuntu container to test areas that need a Linux filesystem
and common utilities but not a real desktop session:

- Initial `/opt/acukids` repository generation.
- File ownership and permissions where the container runtime supports them.
- Configuration validation and atomic replacement.
- Versioned migration and no-op rerun behavior.
- Git and changelog preservation.
- Apply and rollback state transitions with service commands mocked.
- Concurrency locking and interrupted-operation recovery.
- Package-name availability checks that do not require a running desktop.

Containers do not adequately represent a booted Ubuntu Desktop system. They
must not be used to approve GDM, Wayland, dconf session selection,
NetworkManager activation, snap confinement, Firefox GUI policy behavior,
timekpr enforcement, or reboot behavior.

## 3. Disposable Ubuntu Desktop VM tests

Create a golden Ubuntu 26.04 Desktop virtual machine using the official Desktop
ISO. QEMU/KVM with libvirt, VirtualBox, VMware, or another snapshot-capable
hypervisor is suitable. Multipass can help with general Ubuntu testing, but its
normal cloud-image environment is less representative of a stock Desktop
installation for this project.

Suggested lifecycle:

1. Install stock Ubuntu Desktop with a normal fallback user.
2. Install only the access mechanism needed by the test harness, if any.
3. Shut down and create a clean-base snapshot.
4. Start the VM and serve the candidate installer from a local or staging URL.
5. Exercise the same URL-based install path intended for users.
6. Reboot and collect system-state assertions.
7. Perform required graphical-session checks.
8. Export test logs and results without credentials.
9. Restore the clean-base snapshot before the next scenario.

Official references:

- [Ubuntu 26.04 release images](https://en.releases.ubuntu.com/releases/26.04/)
- [Ubuntu Desktop installation guide](https://ubuntu.com/desktop/docs/en/latest/tutorial/install-ubuntu-desktop/)
- [Multipass snapshot behavior](https://documentation.ubuntu.com/multipass/latest/explanation/snapshot/)

### Automated system-state assertions

After deployment and reboot, verify:

- Expected administrator, fallback, and child accounts exist.
- Group membership and home ownership match policy.
- Fallback-account visibility metadata matches the requested state.
- Firefox is installed from the intended source rather than the snap wrapper.
- Mozilla repository, signing key, and apt preference are active.
- Firefox policy JSON is valid and includes the local homepage exception.
- systemd-resolved and NetworkManager use the configured DNS policy.
- timekpr-next is active and every child has the configured schedule.
- The child dconf database compiles and is selected for child sessions.
- Unattended upgrades and reboot policy are enabled.
- `/opt/acukids` is a valid Git repository with expected ownership, history,
  configuration, scripts, changelog, and rollback state.
- The deployment result contains no unreported required-subsystem failure.

### Stateful acceptance sequence

Use one scenario to exercise lifecycle behavior:

1. Complete a fresh deployment.
2. Add a child, site, app, and custom time limit.
3. Record canonical state and Git history.
4. Rerun the installer and verify all custom state and history remain.
5. Apply another change and verify live state converges.
6. Roll back and verify canonical and live state match the prior version.
7. Interrupt an apply and verify recovery.
8. Start concurrent operations and verify locking.

## 4. Graphical-session checks

Initially maintain a short manual release checklist for behavior that requires
GDM and a real Wayland session:

- Child accounts appear in the login picker.
- The fallback account can be hidden and restored.
- A child can log in with the configured PIN.
- Child dconf restrictions are active while administrator settings remain
  normal.
- The authoritative child app menu contains only approved applications.
- Approved applications remain launchable after reconciliation.
- Firefox opens the local homepage, allows approved sites, and blocks an
  unapproved site.
- Administrator Chromium remains unrestricted.
- timekpr warning and lockout behavior operate as documented.

GUI automation may be added later, but it should supplement rather than obscure
clear system-state assertions. Screenshot and input-driven tests are generally
more timing-sensitive than file, account, service, and policy checks.

## 5. Explicit automation mode

An eventual noninteractive mode would make repeatable VM testing possible while
leaving the human interface unchanged:

```bash
# Human installation remains simple.
curl -fsSL https://example.invalid/acukids-deploy.sh | sudo bash

# Test-only or managed automation supplies explicit validated answers.
sudo bash acukids-deploy.sh \
  --config /run/acukids-test/config.json \
  --noninteractive \
  --no-reboot
```

The automated interface should:

- Require an explicit flag.
- Validate the complete configuration before mutation.
- Reject missing answers rather than inventing values.
- Never print secrets.
- Support suppressing reboot.
- Produce a machine-readable result report.

## 6. Single-file release packaging

The distributed installer should remain one self-contained file. Internal
source organization can change without altering that product requirement.

If embedded artifacts become difficult to maintain, a future implementation
may:

1. Store generated scripts, configuration, HTML, and agent instructions as
   separately testable templates.
2. Build a deterministic `acukids-deploy.sh` artifact from those sources.
3. Verify that the artifact is current and reproducible in CI.
4. Publish the artifact at a stable URL with an optional integrity-checking
   workflow.

Do not split the source merely for aesthetics. Adopt this structure only if the
build is deterministic, the generated script is reviewed and tested, and the
end-user command remains equally simple.

## 7. Suggested cadence

- Every edit: current host-safe static and artifact tests.
- Every proposed change: mocked command tests and container integration tests.
- Every release candidate: clean Desktop VM deployment, reboot, rerun,
  rollback, and automated system assertions.
- Before wider rollout: manual GUI acceptance in a VM and testing on at least
  one representative physical machine for graphics, Wi-Fi, audio, firmware,
  suspend/resume, and touchscreen behavior where relevant.

## Future completion criteria

- Mocked and container tests cover the remaining failure, migration,
  transaction, and concurrency paths identified in the active remediation
  tracker; already-covered host-safe cases should not be duplicated merely for
  completeness.
- A clean VM can install from the published-style URL without developer
  intervention beyond the selected interface.
- Fresh install, reboot, rerun, configuration change, rollback, and interrupted
  recovery pass on Ubuntu 26.04 Desktop.
- Manual or automated graphical checks match the documented threat model.
- The tested installer artifact is traceable to committed source and a release
  version.
