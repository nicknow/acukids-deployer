# acuKids desktop-lockdown threat model

## Intended protection

The child account is an authoritative, acuKids-managed environment for young
children. The controls are intended to:

- prevent routine access to administration, software installation, and system
  settings through the normal GNOME interface;
- keep the child application menu and browser experience within the configured
  educational allowlist;
- enforce the configured time window and daily allowance; and
- reduce accidental or casual bypass by a child who is using the normal login
  and desktop.

The administrator account and its password are trusted. Parents and teachers
make persistent changes through `/opt/acukids` and its management/apply process.
The child home application directory is managed state and may be reconciled.

## Out of scope unless separately hardened

The current design is not a defense against a technically capable local user
with physical access. In particular, desktop-level lockdown should not be
described as preventing all execution or access. Potential out-of-scope paths
include:

- virtual consoles and other alternate sessions;
- booting recovery media or changing firmware/boot configuration;
- exploiting an unpatched kernel, driver, application, or physical device;
- launching binaries through an unhidden file association or URI handler;
- removable media and external network devices; and
- bypassing DNS with an application resolver, encrypted DNS, proxy, VPN, or
  literal IP address.

The child account has no sudo membership, but absence of sudo alone is not a
complete execution boundary.

## Documentation rule

User-facing documentation should say that acuKids hides and restricts normal
desktop access for child accounts. It should not claim that a child can never
open a terminal or that DNS filtering cannot be bypassed until those guarantees
are demonstrated by a stronger control design and isolated-system tests.

The deferred VM plan in
[future development testing](future-development-testing.md) is responsible
for exercising these boundaries on the target Ubuntu Desktop release.

## Network filtering guarantees

Cloudflare for Families DNS is a network-level defense-in-depth filter. It
reduces exposure to malware and adult-content domains for ordinary applications
using the machine resolver. It is not, by itself, an enforced egress firewall.

The child Firefox allowlist is the stronger browser-specific control: Firefox
blocks URLs outside the configured exceptions, including links reached from an
approved site. Other applications do not inherit that Firefox policy.

The current design does not claim to prevent every bypass involving encrypted
DNS/DoH, application-specific resolvers, proxies, VPNs, literal IP addresses,
new network devices, or third-party/CDN domains required by an approved site.
Such domains should be reviewed and explicitly allowlisted only when needed.
