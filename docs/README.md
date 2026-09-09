# acuKids documentation

`docs/` contains canonical documentation about how this repository and the
software it produces work. `.ai/` contains reusable instructions for AI
contributors. Agent guidance should link here rather than duplicate project
knowledge.

## Documentation map

- [Project architecture](architecture.md) explains the deployment lifecycle,
  generated control repository, and configuration boundaries.
- [Threat model](threat-model.md) defines what the child lockdown is and is not
  intended to defend against.
- [Repository maintenance](maintenance.md) describes safe development and
  validation practices for this source repository.
- [Branding](branding.md) documents logo and wallpaper deployment, GDM
  integration, asset verification, and VM acceptance checks.
- [Child desktop experience](child-desktop.md) documents the child dock,
  logout launcher, and removal of desktop clutter.
- [Homepage links](homepage-links.md) documents owner-managed child homepage
  tiles, whitelist coverage, and additive defaults.
- Historical remediation task lists are kept in the task workspace rather than
  as permanent canonical documentation.
- [Future development testing](future-development-testing.md) records the
  deferred mocked, container, virtual-machine, and release-testing plan.
- [Future development architecture](future-development-architecture.md)
  records the planned control-plane, parent UI, local homepage, and update
  direction.
- [Deployment guide](../DEPLOYMENT_GUIDE.md) is the complete operator runbook.
- [Quick reference](../QUICK_REFERENCE.md) is the day-to-day administrator
  command card.
- [AI administration guide](../ADMIN_AGENT_GUIDE.md) explains how an operator
  uses an AI coding tool on a deployed machine.
- [README](../README.md) gives the project overview and quick start.

The existing root guides remain in place so established links and distribution
workflows stay backward compatible.
