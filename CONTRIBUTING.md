# Contributing to acuKids

acuKids is intended to be useful to real families. Reports from people who install it, operate it, or test it on Ubuntu are especially valuable.

## Report a problem or suggestion

Please use the repository's GitHub Issues page to report bugs, deployment failures, confusing behavior, documentation problems, and ideas for improvements. Search existing issues first, then include:

- What you expected and what actually happened.
- Ubuntu version and desktop environment.
- The acuKids script build shown at the start of the installer and in `/opt/acukids/config/system-meta.json`.
- Relevant commands, error messages, and a sanitized excerpt of `/var/log/acukids-deploy.log`.
- Whether the issue occurred during a fresh install, reconciliation, or normal administration.

Never include passwords, PINs, tokens, private keys, or other personal data in an issue or pull request.

## Propose changes

Small fixes and documentation improvements are welcome through GitHub pull requests. For larger behavior changes, open an issue first so the design and scope can be discussed. Please explain how the change affects children, parents, existing deployments, and rollback.

#### Remember the User Audience

acuKids isn't built for the power user. The power user may use this repo as a getting started base, but they aren't the audience. I'm a power user I've thought of hundred cool ideas. But, ultimately, if it doesn't make it easier for the parents to setup out-of-the-box or easier for the kids to use I'm not interested.

This doesn't mean those ideas are bad. Feel free to fire up an agent and have it go to work creating an extension script or otherwise customizing your install. Share the scripts, for sure. But ultimately the only things getting deployed through this script are things that someone has implemented in a manner that they add functionality while not adding (and preferrably reducing) complexity for parents and kids.

## Development workflow

1. Read [AGENTS.md](AGENTS.md), [README.md](README.md), and the relevant documentation under `docs/`.
2. Make the smallest focused change possible. `acukids-deploy.sh` is both the installer and the template generator for `/opt/acukids`.
1. Increment `SCRIPT_BUILD` for every installer change.
2. Run the relevant tests, including:

   ```bash
   bash -n acukids-deploy.sh
   tests/test_round3_static.sh
   ```

3. Test system-configuration changes on a disposable Ubuntu 26.04 Desktop VM; do not run the deployment script on your everyday computer.
4. Describe the testing performed in the pull request.

The `main` branch is the stable user channel. Use the project's pre-release branch for changes/updates/fixes that have not been fully tested and released.