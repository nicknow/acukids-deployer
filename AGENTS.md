# Repository guide for AI contributors

This repository contains the acuKids Ubuntu deployment script and its operator
documentation. Start with [README.md](README.md), then use
[docs/README.md](docs/README.md) to find canonical project documentation.

## Conventions

- Treat `acukids-deploy.sh` as both the installer and the generator for the
  deployed `/opt/acukids` control repository. Preserve its generated files and
  runtime behavior unless the task explicitly requires a behavioral change.
- Keep canonical knowledge about the software in `docs/` or the existing
  operator guides. Keep reusable agent-only guidance in `.ai/`, referencing
  canonical docs instead of copying them.
- Put reusable prompts in `.ai/prompts/` and reusable procedures in
  `.ai/workflows/`.
- Put task-specific notes and artifacts in `.work/<agent-name>/`. Each agent
  must use a separate directory. Never make source, builds, tests, or scripts
  depend on `.work/` or on `.ai/{scratch,cache,logs}/`.
- When multiple agents collaborate, divide file ownership before editing,
  communicate shared assumptions, and integrate only reviewed results.
- Validate shell changes with `bash -n acukids-deploy.sh`; use ShellCheck when
  available. A live deployment test requires a disposable Ubuntu 26.04 system.

If future developers or agents will benefit from information, commit it. If it
is useful only for the current task, keep it in the temporary workspace.
