# Using AI Coding Agents to Manage acuKids

The acuKids deployment pre-installs three agentic coding harnesses on the
**admin account**:

- **Claude Code** (`claude`)
- **Codex CLI** (`codex`)
- **OpenCode** (`opencode`)

Any of them can safely read and modify the acuKids configuration because
`/opt/acukids/AGENTS.md` (symlinked as `CLAUDE.md`) documents the entire
system in a format these tools are designed to read automatically when
launched inside that directory.

You are not required to use any of these - the `acukids-manage.sh` script
and manual editing work exactly the same way. This is simply a faster,
conversational alternative for admins who prefer it.

---

## Getting started

```bash
cd /opt/acukids
claude       # or: codex   /   opencode
```

The tool will pick up `AGENTS.md` / `CLAUDE.md` automatically and understand:
- What accounts exist and how they're structured
- Where the canonical configuration lives (`config/`)
- How to apply changes safely (`scripts/acukids-apply.sh`)
- How to roll back (`scripts/acukids-apply.sh --rollback`)
- What it should NOT do without asking you first (see below)

---

## Example requests you can type in plain English

- "Add a new child account called Maya with PIN 7734."
- "Remove the child account 'jake' - he doesn't use this computer anymore."
- "Let the kids visit storylineonline.net as well."
- "Give Emma 3 hours on Saturdays instead of 2."
- "Hide Krita from the kids' app grid, it's too advanced for now."
- "I installed a new app, make it visible to the kids."
- "Hide the original installer account from the login screen."
- "Show me everything that's changed in the last week."
- "Something broke after your last change, undo it."

The agent will:
1. Read the relevant file(s) under `config/`.
2. Make the edit - for a new app, it will look up the app's *real*
   `.desktop` filename via `dpkg -L <package> | grep '\.desktop$'` rather
   than guessing (guessed filenames have caused real bugs in this
   deployment before - see `AGENTS.md` for why this matters).
3. Run `sudo /opt/acukids/scripts/acukids-apply.sh` to apply it live.
4. Confirm the change was logged in `CHANGELOG.md`.

---

## Guardrails built into AGENTS.md

The agent is instructed to **ask you first** before it will:
- Turn off DNS filtering, the browser whitelist, or desktop lockdown
- Delete the original installer (fallback) account (hiding it from the
  login picker is fine to do without asking - it's reversible and the
  account keeps working if its name is typed manually)
- Change which browser children use
- Grant any child account sudo/admin rights
- Modify `/etc/sudoers.d/acukids-admin`

If an agent proposes any of these, treat it as a signal to pause and
review carefully before approving.

---

## Reviewing what an agent changed

```bash
cd /opt/acukids
git log --oneline          # if the agent committed its changes
git diff                    # uncommitted changes
cat CHANGELOG.md            # human-readable action log
```

If you don't like a change and it hasn't been committed yet, you can
discard it with `git checkout -- config/` or use the built-in rollback:

```bash
sudo /opt/acukids/scripts/acukids-apply.sh --rollback
```

If an owner-edited management script has a syntax error and cannot start, the
owner can restore the last committed copy directly from the local repository
(this does not execute the broken script):

```bash
cd /opt/acukids
git show HEAD:scripts/acukids-apply.sh > /tmp/acukids-apply.sh.restore
sudo install -o root -g acukids-admin -m 0775 /tmp/acukids-apply.sh.restore scripts/acukids-apply.sh
```

---

## Installing a different harness

Only Claude Code, Codex, and OpenCode are installed automatically. To add
another (e.g. GitHub Copilot CLI), install it normally for the admin
account - it will still be able to read `/opt/acukids/AGENTS.md` /
`CLAUDE.md` as long as it supports reading a repository-root instructions
file, or you can simply tell it to open and read that file first.
