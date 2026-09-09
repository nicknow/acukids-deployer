# Child desktop experience

Child accounts receive a small, predictable GNOME desktop focused on the
applications already approved by the acuKids whitelist. The dock is fixed to
the bottom and favorites use each application's installed `.desktop` name and
icon; no parallel acuKids naming or category system is introduced. Files and
Font Viewer remain in the app grid but are intentionally omitted from the
everyday dock.

The dock also includes **I'm all done**, a system launcher that calls GNOME's
normal logout command. GNOME displays its confirmation prompt, so an
accidental click does not immediately end a session.

Desktop icons for Home, Trash, and mounted volumes are disabled for children.
The child dconf database locks these presentation settings, while parent and
fallback accounts retain their normal desktop preferences.

The launcher and UI policy are installed during a full deployment/reconcile.
If an administrator adds or removes an application in
`/opt/acukids/config/whitelist-apps.conf`, the app grid follows that file after
`acukids-apply.sh`; the dock is regenerated when the deploy script is rerun so
newly approved applications can become favorites.

Installer upgrades add newly supplied applications without replacing the
owner's choices. An explicit removal is recorded in
`config/blacklist-apps.conf`, which prevents that app from returning on a
future upgrade. Use `acukids-manage.sh add-app` to remove the blacklist entry
and restore an app intentionally.

## VM checks

After a build 14 or newer deployment and reboot, log in as each child and
confirm:

1. The dock is along the bottom and shows the approved applications with their
   normal names and icons.
2. **I'm all done** is visible. Selecting it shows GNOME's logout confirmation;
   cancel leaves the session active, and confirming returns to GDM.
3. Home, Trash, and mounted-volume icons are not present on the desktop.
4. A child cannot change the dock position, favorites, or desktop-icon choices.
5. The parent account still has its ordinary Ubuntu desktop and application
   access.
