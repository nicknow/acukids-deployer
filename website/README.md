# acuKids website

This directory contains the user-facing static website published through
GitHub Pages.

- `index.html` contains the page structure and copy.
- `styles.css` contains the responsive visual design and accessibility modes.
- `script.js` provides the mobile menu and copy-command interaction.

The site reuses the canonical `acukids-logo.png` from the repository root; that
asset also belongs to the installer and deployed child environment, so it is
not duplicated here. The Pages workflow stages the website files and shared
logo together before publishing.

GitHub requires the deployment workflow itself to remain at
`.github/workflows/pages.yml`.
