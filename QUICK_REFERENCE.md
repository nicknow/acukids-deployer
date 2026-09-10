# acuKids Quick Reference Card

*Print this page and keep it near the computer.*

---

## Logging in

| Who | How |
|---|---|
| A child | Click their name on the login screen, enter their 4-digit PIN |
| Admin (you) | Click the admin username, enter the admin password |
| Recovery/fallback | The original account created during Ubuntu install (bottom of list) |

---

## Screen time rules (default)

| Day | Daily limit | Allowed hours |
|---|---|---|
| Monday-Friday | 1 hour | 6:00 AM - 7:00 PM |
| Saturday-Sunday | 2 hours | 6:00 AM - 7:00 PM |

A warning appears a few minutes before time runs out. The screen locks
automatically when time is up; it unlocks again at the start of the next
allowed window.

---

## Approved websites (children's Firefox, default set)

- PBS Kids - pbskids.org
- National Geographic Kids - kids.nationalgeographic.com
- Kids Games by Nicknow - nicknow.net/games
- NASA Space Place - spaceplace.nasa.gov
- Unite for Literacy - uniteforliteracy.com
- Chrome Music Lab - musiclab.chromeexperiments.com
- PhET Simulations - phet.colorado.edu
- NGA Paint-N-Play - nga.gov
- Smithsonian Science - ssec.si.edu
- NOAA Educational Games - noaa.gov

Everything else is blocked, even if a link is clicked from an approved site.
Add more anytime with `add-site` (see below) - the list above reflects a
fresh install's defaults, so it may differ from what's currently allowed on
this machine.

---

## Installed educational software (by age)

**Ages 3-5 (Preschool)**
- GCompris - counting, letters, shapes, puzzles
- Tux Paint - simple drawing

**Ages 5-7 (Early Primary)**
- Tux Math - arithmetic practice
- Tux Type - typing practice
- Stellarium - explore stars and planets
- KTurtle - learn programming with turtle graphics
- Krita - digital art (more advanced)
- Audacity - record and play with sound

---

## Common admin tasks

Open a terminal on the **admin account**, then:

```bash
# Add a child
sudo /opt/acukids/scripts/acukids-manage.sh add-child <name> <pin>

# Reset today's time budget to the configured daily allowance
sudo /opt/acukids/scripts/acukids-manage.sh reset-time <name>

# Change a PIN
sudo /opt/acukids/scripts/acukids-manage.sh set-pin <name> <newpin>

# Allow a new website
sudo /opt/acukids/scripts/acukids-manage.sh add-site <domain.com>

# Hide/show the original installer (fallback) account at login
sudo /opt/acukids/scripts/acukids-manage.sh hide-fallback-account <username>
sudo /opt/acukids/scripts/acukids-manage.sh show-fallback-account <username>

# See all children and their limits
/opt/acukids/scripts/acukids-manage.sh list-children
```

---

## Quick fixes

| Problem | Fix |
|---|---|
| Child locked out early | `sudo /opt/acukids/scripts/acukids-manage.sh reset-time <name>` |
| Forgot admin password | Log in with the original fallback account, reset via Settings |
| A site won't load that should work | Check spelling in whitelist, then re-apply (see guide) |
| An installed app isn't showing for kids | Find its real name with `dpkg -L <package> \| grep '\.desktop$'`, add it to the whitelist, re-apply |
| Original account showing at login and you don't want it to | `sudo /opt/acukids/scripts/acukids-manage.sh hide-fallback-account <username>` |
| Something feels "broken" after a change | `sudo /opt/acukids/scripts/acukids-apply.sh --rollback` |

---

## Want an AI assistant to make changes for you?

Log in as admin, open a terminal, and run:

```bash
cd /opt/acukids && opencode
```

You don't have to use `opencode`. Try any of them. OpenCode is referenced here because at this time it offers some free models with no account required. This allows anyone to get started using it without having to use a credit card or spend any money.

Then just type what you want in plain English, e.g. *"Add a child named
Leo with PIN 1234"* or *"Let kids use wikipediakids.org too."*

(Codex and Claude also work - swap `claude` for `codex` or `opencode`.)

---

*For full details, see DEPLOYMENT_GUIDE.md and ADMIN_AGENT_GUIDE.md.*
