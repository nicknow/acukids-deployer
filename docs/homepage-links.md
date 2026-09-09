# Child homepage links

The generated child homepage is driven by `/opt/acukids/config/homepage-links.json`.
Each entry has a stable `id`, a display `label`, and an HTTPS `url`. The URL's
host/path must also be present in `whitelist-sites.conf`; the browser allowlist
remains the security boundary.

Installer defaults are recorded in `installer-default-homepage-links.json`.
Future installer updates add new defaults without replacing owner edits. A
removed default ID is recorded in `blacklist-homepage-links.conf` so it is not
reintroduced.

Use the management tool as root:

```bash
sudo /opt/acukids/scripts/acukids-manage.sh add-site example.org
sudo /opt/acukids/scripts/acukids-manage.sh add-homepage-link example "Example" "https://example.org/"
sudo /opt/acukids/scripts/acukids-manage.sh remove-homepage-link example
```

Every command applies the change immediately and creates the normal rollback
snapshot. If the homepage was manually customized, apply preserves it; edit or
remove the custom page before asking acuKids to regenerate the managed page.
