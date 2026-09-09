# acuKids

**For families:** visit the [acuKids website](https://nicknow.github.io/acukids-deployer/) for a friendly overview and guided start.

<table>
<tr>
A safe, locked-down educational computing environment for children ages 3-7, built on **Ubuntu 26.04 LTS ("Resolute Raccoon")** with a curated set of educational applications and whitelisted websites. One script converts a plain Ubuntu Desktop install into a fully configured acuKids machine - kid-safe browsing, screen-time limits, educational software, and an ongoing management layer that a human admin (or an AI agent) can safely reconfigure over time.    
   </tr>
   <tr><img src="acukids-logo.png" alt="acuKids Logo" width=250 align="top" /></tr>
</table>

> **Beta notice:** acuKids is extensively tested and is being used by kids
> today, but it is still beta software. Expect occasional bugs, review the
> configuration before relying on it, and report problems or suggestions
> through [GitHub](https://github.com/nicknow/acukids-deployer/issues).

Licensed under the [MIT License](LICENSE).

---

## Why and Ambition

Because any parent should be able to give their child a computer and feel safe. I started this just wanting to configure a computer for my daughters to play with, my six year old kept asking ("Dad, when is **my** comptuer going to be ready?") And I wanted her to have a computer to play with and learn on and I wanted it to be safe. I also wanted to use an old computer I had sitting around. I didn't want to hand her a newer MacBook or intro her to Windows yet. I just wanted something for her to do math and reading games and visit PBS Kids, etc.

acuKids is what came of that initial itch. I got it working - thanks to Claude, GPT Luna, and GPT Sol - fairly quickly (lots of credit to Claude for much of the original design/scripting and GPT Luna for lots of refinement and hardening and new features.) I also used  OpenCode Big Pickle to troubleshoot/tweak the actual install and then provide feedback to the dev agent to change the script.

And then I decided it should really be something anyone could use. Why not? There are working computers you can grab on Facebook Marketplace for under $200 w/ a monitor and even older laptops. You can probably find them cheaper to free at yard sales and Buy Nothing Facebook groups. These computers work, they just aren't the latest tech. acuKids exist to let parents take those computers and make them a learning opportunity for their children.

This isn't about my children. They're going to grow up in a household full of computers and technology and parents who ensure they aren't browsing stuff they shouldn't and using computers for learning and managing their screen time. But doing all that is hard. I'm inspired to do this for all the parents who want to give their kids that but don't have the time and money. The parents that work two jobs each and barely are home and struggle to make ends meet, but really want their kids to learn. acuKids is for everyone, it's about ensuring any parent that wants to give their kid a computer and a chance to learn can do so safely.

I started this with an age range of 3-7 and more realistically it's probably 4-8. Eventually I *may* want to expand it to cover adolescents and teens, I just had to have a place to start. And I haven't decided how I want to handle broader access, probably because I can't easily test it out (like I can with a 4 year old and 6 year old who like to hangout in my office.)

---

## What you get

- **Multiple child accounts**, each with a simple 4-digit PIN login
- **A separate admin account** for teachers/parents (the original Ubuntu installer account is kept as a fallback login; you choose during setup whether it also stays hidden from the login picker)
- **Cloudflare for Families DNS filtering** (blocks malware + adult content)
- **A locked-down Firefox** for kids, restricted to a strict whitelist of approved educational sites, plus an unrestricted Chromium for the admin
- **A locked-down desktop and app menu** for children - only approved educational/creative apps are visible, discovered automatically from each installed package rather than guessed, so it stays accurate even as package `.desktop` filenames change upstream
- **Screen time limits** via timekpr-next (1 hr/weekday, 2 hr/weekend, 6:00 AM-7:00 PM window by default, all adjustable)
- **Automatic security updates** with unattended overnight reboots
- **Pre-installed AI coding agents** (Claude Code, Codex CLI, OpenCode) on the admin account, pointed at a self-documenting config repo so you can reconfigure the system by just describing what you want in plain English
- **Full change history and rollback** via a local git repo and an apply/snapshot system - no live-editing of system files required

---

## Repository contents

| File                   | Purpose                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------- |
| `acukids-deploy.sh`    | The main deployment script. Run once on a fresh Ubuntu 26.04 Desktop install. Self-contained; asks all setup questions up front, then runs unattended. |
| `DEPLOYMENT_GUIDE.md`  | Full step-by-step instructions: installing Ubuntu, running the script, first login, and troubleshooting. **Start here.** |
| `QUICK_REFERENCE.md`   | A printable one-page cheat sheet for teachers/parents - login instructions, screen-time rules, and common commands. |
| `ADMIN_AGENT_GUIDE.md` | How to use Claude Code, Codex, or OpenCode to manage the system conversationally after deployment.   |
| `CONTRIBUTING.md`      | How to report problems and propose changes to this repository.                                      |
| `website/`             | Source for the family-facing GitHub Pages website.                                                   |
| `docs/`                | Canonical architecture, threat model, and maintenance documentation - see [docs/README.md](docs/README.md). |
| `LICENSE`              | MIT License.                                                                                         |

Once deployed, the script also creates `/opt/acukids/` on the target
machine - the live configuration repo, documented in its own
`AGENTS.md` / `CLAUDE.md`, which is what the management scripts and any
AI agent actually read and write.

---

## Quick start

1. Install a plain Ubuntu 26.04 LTS ("Resolute Raccoon") Desktop on the target machine (see
   [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md#3-step-1---install-plain-ubuntu-2604-lts-desktop)).
1. Copy `acukids-deploy.sh` to the machine (USB drive, or host it and
   `curl` it down).
1. Run it:

   ```bash
   sudo bash acukids-deploy.sh
   ```

   For the latest stable script directly from GitHub, you can instead run:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/nicknow/acukids-deployer/main/acukids-deploy.sh | sudo bash
   ```
1. Answer the setup questions (hostname, admin account, child accounts +
   PINs), confirm the summary, and let it run to completion.
1. Reboot when prompted. Done.

For the full walkthrough, see [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).
If you find a problem or have an improvement idea, please use GitHub Issues;
see [CONTRIBUTING.md](CONTRIBUTING.md) for what information to include.

---

## Managing an existing acuKids machine

```bash
# Add a child
sudo /opt/acukids/scripts/acukids-manage.sh add-child <name> <pin>

# Allow a new website
sudo /opt/acukids/scripts/acukids-manage.sh add-site <domain.com>

# Hide the original installer account from the login picker (still usable
# by typing the username manually)
sudo /opt/acukids/scripts/acukids-manage.sh hide-fallback-account <username>

# Or just ask an AI agent to do it for you
cd /opt/acukids && claude
```

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) and [ADMIN_AGENT_GUIDE.md](ADMIN_AGENT_GUIDE.md) for details.

---

## License

Copyright (C) 2026 Nicolas A. Nowinski.

This project is licensed under the [MIT License](LICENSE) - free to use, modify, and distribute, with no warranty.

Note: acuKids configures third-party services (Cloudflare for Families DNS, Mozilla's Firefox APT repository) and installs third-party educational software and AI coding tools (Claude Code, Codex CLI, OpenCode). Those components are governed by their own respective licenses and terms of service, which are not covered by this project's MIT License.

---

## Inspiration Credit

I would give a lot of credit to [DHH's](https://x.com/dhh) work on [Omarchy](https://omarchy.org/) for inspiring me to think of what could be really done. I stuck with Ubuntu given my target users and that fact that I don't want to actually *own* a Linux distribution, I'm happy just configuring a Ubuntu instance. But, fair warning, don't be surprised if I get the itch in a few months and do want to do a full distribution (we'll see or maybe someone else is inspired by this and does it and I don't have to!) I also give credit to [Edubuntu](https://www.edubuntu.org/) that has helped make an education friendly Ubuntu distribution available for schools, but it's primarily focused on helping schools deploy and manage a fleet of educational desktops where as acuKids is about a single personal device for kids.



## Dedicated to

This project is dedicated to my late father, [Ed Nowinski](https://en.wikipedia.org/wiki/Edmund_H._Nowinski), and my mom, Judy Nowinski. They allowed me to grow up in a household full of love and support and computers. They always encouraged me. And it is because of them and their support and their sacrifice that I get to live this incredible life today. And to their granddaughters, Emilia and Evelyn, who are my inspiration for acuKids and so much more - you two are my everything - and Nicole - my incredible loving caring wife - who puts up with all of this stuff!. 
