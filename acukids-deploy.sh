#!/usr/bin/env bash
#
# acukids-deploy.sh
#
# Copyright (C) 2026 Nicolas A. Nowinski. All Rights Reserved.
# Licensed under the MIT License - see LICENSE in the project root.
#
# Converts a stock Ubuntu 26.04 LTS "Resolute Raccoon" Desktop installation
# into an "acuKids" safe educational computer for children ages 3-7.
#
# Usage:
#   sudo bash acukids-deploy.sh
#   curl -fsSL https://<your-host>/acukids-deploy.sh | sudo bash
#
# Must be run as root (via sudo) on a freshly installed Ubuntu 26.04 LTS
# Desktop system with an active internet connection.
#
# NOTE ON GNOME 50 / WAYLAND-ONLY: 26.04 ships GNOME 50 and drops the
# GNOME-on-X11 session entirely (Wayland-only). GDM config, dconf, and
# timekpr-next are expected to behave the same way as on 24.04, but this
# release is new enough that package names/behavior should be verified on
# a test machine before mass deployment - see the "Before you deploy at
# scale" section of README.md.
#
set -uo pipefail

# ---------------------------------------------------------------------------
# Globals / constants
# ---------------------------------------------------------------------------
ACUKIDS_HOME="${ACUKIDS_HOME:-/opt/acukids}"
LOG_FILE="/var/log/acukids-deploy.log"
CHILD_GROUP="acukids-children"
DCONF_PROFILE_NAME="acukids-child"
SCRIPT_VERSION="0.8-beta"
# Increment for every change to this installer. This integer is printed at
# startup and recorded in the generated control-repository metadata.
SCRIPT_BUILD=27
CONTROL_SCHEMA_VERSION=1
ACUKIDS_ASSET_BASE_URL="${ACUKIDS_ASSET_BASE_URL:-https://raw.githubusercontent.com/nicknow/acukids-deployer/main}"
ACUKIDS_LOGO_SHA256="c8cfd01b5b179e8d9bb28de739be80bd83a37201ea1ff7fa99a72c1dbf6e1b78"
ACUKIDS_WALLPAPER_SHA256="5dffa1ad277a57cc59df74756426d9f635b88721ac14ab6f44ec500f830a72a1"
BRANDING_DIR="/usr/share/acukids/branding"
TIMEKPR_PPA="ppa:mjasnik/ppa"
TIMEKPR_MIN_VERSION="0.5.10"
TIMEKPR_INSTALLED_VERSION="unavailable"
RERUN_BACKUP_DIR="/var/backups/acukids"
CLAUDE_CODE_VERSION="2.1.263"
CODEX_VERSION="0.153.4"
OPENCODE_VERSION="1.18.29"
UBUNTU_CODENAME_REQUIRED="resolute"   # Ubuntu 26.04 LTS "Resolute Raccoon"
UBUNTU_MIN_RAM_GB=6                    # 26.04 raised the minimum from 4GB to 6GB
EXISTING_DEPLOYMENT=false
RERUN_MODE=false
INTERRUPTED_INSTALL=false
INSTALL_STATE_FILE="/var/lib/acukids-install-state.json"
OPTIONAL_FAILURES=()

WHITELIST_SITES_DEFAULT=(
  "pbskids.org"
  "kids.nationalgeographic.com"
  "nicknow.net/games"
  "spaceplace.nasa.gov"
  "nasa.gov"
  "uniteforliteracy.com"
  "musiclab.chromeexperiments.com"
  "phet.colorado.edu"
  "nga.gov"
  "ssec.si.edu"
  "noaa.gov"
)

HOMEPAGE_LINKS_DEFAULT_JSON='[
  {"id":"pbs-kids","label":"PBS Kids","url":"https://pbskids.org/"},
  {"id":"natgeo-kids","label":"Nat Geo Kids","url":"https://kids.nationalgeographic.com/"},
  {"id":"nicknow-games","label":"Kids Games by Nicknow","url":"https://nicknow.net/games/"},
  {"id":"nasa-space-place","label":"NASA Space Place","url":"https://spaceplace.nasa.gov/"},
  {"id":"unite-for-literacy","label":"Unite for Literacy","url":"https://uniteforliteracy.com/"},
  {"id":"chrome-music-lab","label":"Chrome Music Lab","url":"https://musiclab.chromeexperiments.com/"},
  {"id":"phet-simulations","label":"PhET Simulations","url":"https://phet.colorado.edu/en/simulations/filter?locale=en&levels=elementary-school&type=html&a11yFeatures=accessibility"},
  {"id":"nga-paint-n-play","label":"NGA Paint-N-Play","url":"https://nga.gov/games/paint-n-play/"},
  {"id":"smithsonian-science","label":"Smithsonian Science","url":"https://ssec.si.edu/node/583"},
  {"id":"noaa-educational-games","label":"NOAA Educational Games","url":"https://www.nesdis.noaa.gov/about/k-12-education/educational-games-simulations"}
]'

# Educational / creative apps kept visible on child accounts.
# Format: desktop-file-basename (without path) -> comment
WHITELIST_APPS_DEFAULT=(
  "org.kde.gcompris.desktop"
  "tuxpaint.desktop"
  "tuxmath.desktop"
  "tuxtype.desktop"
  "org.kde.krita.desktop"
  "audacity.desktop"
  "org.stellarium.Stellarium.desktop"
  "org.gnome.Firefox.desktop"
  "firefox.desktop"
  "org.gnome.Nautilus.desktop"
  "org.gnome.font-viewer.desktop"
  "simple-scan.desktop"
)

# apt packages to attempt (failures are logged, not fatal - install_packages
# tries each individually and skips anything unavailable, so a renamed or
# retired package will not abort the deployment).
EDU_PACKAGES=(
  gcompris-qt
  tuxpaint
  tuxpaint-config
  tuxmath
  tuxtype
  krita
  audacity
  stellarium
)

BASE_PACKAGES=(
  software-properties-common
  dconf-cli
  dconf-editor
  gnome-tweaks
  curl
  wget
  git
  jq
  ca-certificates
  gnupg
  apt-transport-https
  unattended-upgrades
  apt-listchanges
  nodejs
  npm
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "FATAL: $*"
  exit 1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root. Try: sudo bash $0"
  fi
}

INSTALL_LOCK_FILE="/run/lock/acukids.lock"
acquire_lock() {
  install -d -m 0755 "$(dirname "$INSTALL_LOCK_FILE")" || die "Unable to create acuKids lock parent."
  exec 9>"$INSTALL_LOCK_FILE" || die "Unable to open acuKids lock."
  flock -n 9 || die "Another acuKids operation is already running; retry after it completes."
  export ACUKIDS_LOCK_HELD=true
}

ensure_interactive_stdin() {
  # If stdin isn't a real terminal (e.g. the script was launched with
  # `curl ... | sudo bash`, or via some SSH/CI wrapper), every `read` below
  # would silently get empty input instead of prompting the user - which is
  # exactly what produces a premature "Invalid username" (or similar) error
  # before anything was typed. Reattach stdin to the actual keyboard/TTY.
  if [[ ! -t 0 ]]; then
    if [[ -r /dev/tty ]]; then
      exec < /dev/tty
      log "stdin was not a terminal (likely piped, e.g. curl | sudo bash); reattached input to /dev/tty."
    else
      die "This script needs an interactive terminal to ask setup questions, but none is available (no /dev/tty). If you ran this via 'curl ... | sudo bash', download the file first and run it directly instead: curl -fsSL <url> -o acukids-deploy.sh && sudo bash acukids-deploy.sh"
    fi
  fi
}

require_ubuntu_2604() {
  if ! grep -qi "$UBUNTU_CODENAME_REQUIRED" /etc/os-release 2>/dev/null; then
    log "WARNING: This script targets Ubuntu 26.04 LTS (resolute). Your /etc/os-release:"
    cat /etc/os-release | tee -a "$LOG_FILE"
    read -r -p "Continue anyway? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || die "Aborted by user."
  fi
}

check_ram() {
  local ram_kb ram_gb
  ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  ram_gb=$(( ram_kb / 1024 / 1024 ))
  if (( ram_gb < UBUNTU_MIN_RAM_GB )); then
    log "WARNING: Detected ~${ram_gb}GB RAM. Ubuntu 26.04 Desktop recommends ${UBUNTU_MIN_RAM_GB}GB+."
    read -r -p "Continue anyway? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || die "Aborted by user due to low RAM."
  fi
}

require_internet() {
  log "Checking internet connectivity..."
  if ! curl -fsS --max-time 8 https://archive.ubuntu.com >/dev/null 2>&1; then
    die "No internet connection detected. Connect this machine to the internet and re-run."
  fi
  log "Internet connectivity OK."
}

install_packages() {
  # Attempts to install a list of packages. Failures are logged individually
  # and do not stop the deployment.
  local pkgs=("$@")
  log "Installing packages: ${pkgs[*]}"
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}" >> "$LOG_FILE" 2>&1; then
    log "WARNING: bulk install failed, retrying package-by-package..."
    for p in "${pkgs[@]}"; do
      if DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$p" >> "$LOG_FILE" 2>&1; then
        log "  OK: $p"
      else
        log "  SKIPPED (not available / failed): $p"
        OPTIONAL_FAILURES+=("package:$p")
      fi
    done
  fi
}

asset_has_expected_hash() {
  local path="$1" expected="$2" actual
  [[ -f "$path" ]] || return 1
  actual=$(sha256sum "$path" 2>/dev/null | awk '{print $1}') || return 1
  [[ "$actual" == "$expected" ]]
}

install_branding_asset() {
  local filename="$1" expected="$2"
  local destination="$BRANDING_DIR/$filename" script_dir local_source staged

  if asset_has_expected_hash "$destination" "$expected"; then
    return 0
  fi

  script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
  local_source="$script_dir/$filename"
  staged=$(mktemp "$BRANDING_DIR/.${filename}.XXXXXX") || return 1
  if asset_has_expected_hash "$local_source" "$expected"; then
    cp "$local_source" "$staged" || { rm -f "$staged"; return 1; }
  elif ! curl -fsSL --retry 3 --connect-timeout 10 \
    "$ACUKIDS_ASSET_BASE_URL/$filename" -o "$staged"; then
    rm -f "$staged"
    return 1
  fi
  if ! asset_has_expected_hash "$staged" "$expected"; then
    rm -f "$staged"
    return 1
  fi
  chmod 0644 "$staged" && mv -f "$staged" "$destination" || { rm -f "$staged"; return 1; }
}

install_branding_assets() {
  install -d -m 0755 "$BRANDING_DIR" || return 1
  install_branding_asset acukids-logo.png "$ACUKIDS_LOGO_SHA256" || return 1
  install_branding_asset acukids-wallpaper.png "$ACUKIDS_WALLPAPER_SHA256" || return 1

  local ubuntu_logo=/usr/share/pixmaps/ubuntu-logo-text-dark.svg
  [[ -r "$ubuntu_logo" ]] || ubuntu_logo=/usr/share/pixmaps/ubuntu-logo-text.svg
  [[ -r "$ubuntu_logo" ]] || return 1
  cp "$ubuntu_logo" "$BRANDING_DIR/ubuntu-logo.svg" || return 1
  chmod 0644 "$BRANDING_DIR/ubuntu-logo.svg" || return 1

  local staged
  staged=$(mktemp "$BRANDING_DIR/.acukids-login-logo.XXXXXX") || return 1
  command -v base64 >/dev/null 2>&1 || { rm -f "$staged"; return 1; }
  {
    printf '%s' '<svg xmlns="http://www.w3.org/2000/svg" width="360" height="96" viewBox="0 0 360 96"><image href="data:image/png;base64,'
    base64 -w0 "$BRANDING_DIR/acukids-logo.png"
    printf '%s' '" x="0" y="0" width="96" height="96" preserveAspectRatio="xMidYMid meet"/><rect x="119" y="20" width="2" height="56" rx="1" fill="#ffffff" opacity="0.55"/><image href="data:image/svg+xml;base64,'
    base64 -w0 "$BRANDING_DIR/ubuntu-logo.svg"
    printf '%s' '" x="144" y="16" width="192" height="64" preserveAspectRatio="xMidYMid meet"/></svg>'
  } > "$staged" || { rm -f "$staged"; return 1; }
  chmod 0644 "$staged" && mv -f "$staged" "$BRANDING_DIR/acukids-login-logo.svg" || { rm -f "$staged"; return 1; }
  log "Installed verified acuKids wallpaper and login branding assets."
}

is_valid_username() {
  [[ "$1" =~ ^[a-z][-a-z0-9_]{2,31}$ ]]
}

is_valid_pin() {
  [[ "$1" =~ ^[0-9]{4}$ ]]
}


# ---------------------------------------------------------------------------
# Step 0: Gather ALL configuration up front (no prompts after this point)
# ---------------------------------------------------------------------------
gather_configuration() {
  if [[ -f "$INSTALL_STATE_FILE" && "$EXISTING_DEPLOYMENT" == "false" ]]; then
    gather_interrupted_configuration
    return
  fi
  if [[ "$EXISTING_DEPLOYMENT" == "true" ]]; then
    gather_existing_configuration
    return
  fi

  echo "======================================================================"
  echo " acuKids Deployment - Configuration"
  echo "======================================================================"
  echo "Answer the following questions. Installation will then run to"
  echo "completion with NO further prompts."
  echo "----------------------------------------------------------------------"

  # --- Hostname ---
  read -r -p "Computer name / hostname [acukids]: " HOSTNAME_INPUT
  HOSTNAME_INPUT="${HOSTNAME_INPUT:-acukids}"
  ACUKIDS_HOSTNAME=$(echo "$HOSTNAME_INPUT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  [[ -n "$ACUKIDS_HOSTNAME" ]] || ACUKIDS_HOSTNAME="acukids"
  echo "  -> Hostname will be: $ACUKIDS_HOSTNAME"
  echo

  # --- Detect the original installer account ---
  ORIGINAL_ADMIN_USER="${SUDO_USER:-}"
  if [[ -z "$ORIGINAL_ADMIN_USER" || "$ORIGINAL_ADMIN_USER" == "root" ]]; then
    # Fallback: first non-system user with a home dir
    ORIGINAL_ADMIN_USER=$(awk -F: '$3>=1000 && $3<60000 {print $1}' /etc/passwd | head -n1)
  fi
  HIDE_ORIGINAL_ACCOUNT="false"
  if [[ -z "$ORIGINAL_ADMIN_USER" ]]; then
    log "WARNING: Could not auto-detect the original installer account."
  else
    echo "  -> Detected original Ubuntu installer account: $ORIGINAL_ADMIN_USER"
    echo "     This account will be KEPT (not deleted) but its auto-login"
    echo "     will be disabled. It remains available as a recovery/fallback login."
    read -r -p "     Hide it from the login screen's picker too? It will still work by typing the username manually. [Y/n]: " hide_ans
    [[ "${hide_ans,,}" == "n" ]] && HIDE_ORIGINAL_ACCOUNT="false" || HIDE_ORIGINAL_ACCOUNT="true"
  fi
  echo

  # --- New administrator account ---
  echo "----------------------------------------------------------------------"
  echo "New acuKids administrator account (for teachers/parents)"
  echo "----------------------------------------------------------------------"
  while true; do
    read -r -p "Admin username: " ADMIN_USERNAME
    if is_valid_username "$ADMIN_USERNAME"; then
      if [[ "$ADMIN_USERNAME" == "$ORIGINAL_ADMIN_USER" ]]; then
        echo "  That matches the original installer account. Choose a different username."
        continue
      fi
      break
    fi
    echo "  Invalid username. Use lowercase letters/numbers, start with a letter, 3-32 chars."
  done
  read -r -p "Admin full name [Administrator]: " ADMIN_FULLNAME
  ADMIN_FULLNAME="${ADMIN_FULLNAME:-Administrator}"
  while true; do
    read -r -s -p "Admin password: " ADMIN_PASSWORD; echo
    read -r -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM; echo
    if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" && ${#ADMIN_PASSWORD} -ge 8 ]]; then
      break
    fi
    echo "  Passwords did not match or were too short (min 8 chars). Try again."
  done
  echo

  # --- Child accounts ---
  echo "----------------------------------------------------------------------"
  echo "Child accounts"
  echo "----------------------------------------------------------------------"
  while true; do
    read -r -p "How many child accounts do you want to create? " NUM_CHILDREN
    [[ "$NUM_CHILDREN" =~ ^[0-9]+$ ]] && (( NUM_CHILDREN >= 1 )) && break
    echo "  Enter a whole number of 1 or more."
  done

  CHILD_USERNAMES=()
  CHILD_PINS=()
  for (( i=1; i<=NUM_CHILDREN; i++ )); do
    echo "  --- Child #$i ---"
    while true; do
      read -r -p "  Username for child #$i: " cname
      if is_valid_username "$cname" && [[ "$cname" != "$ADMIN_USERNAME" && "$cname" != "$ORIGINAL_ADMIN_USER" ]]; then
        dup=0
        for existing in "${CHILD_USERNAMES[@]:-}"; do
          [[ "$existing" == "$cname" ]] && dup=1
        done
        [[ $dup -eq 0 ]] && break
        echo "    That username is already used for another child."
      else
        echo "    Invalid or already-used username. Use lowercase letters/numbers, 3-32 chars."
      fi
    done
    while true; do
      read -r -s -p "  4-digit PIN for $cname: " cpin; echo
      read -r -s -p "  Confirm PIN for $cname: " cpin_confirm; echo
      if is_valid_pin "$cpin" && [[ "$cpin" == "$cpin_confirm" ]]; then
        break
      fi
      echo "    PIN must be exactly 4 digits and match confirmation."
    done
    CHILD_USERNAMES+=("$cname")
    CHILD_PINS+=("$cpin")
  done
  echo

  # --- Confirmation ---
  echo "======================================================================"
  echo " Configuration summary"
  echo "======================================================================"
  echo "Script build:            $SCRIPT_BUILD (release $SCRIPT_VERSION)"
  echo "Hostname:               $ACUKIDS_HOSTNAME"
  echo "Original installer acct: ${ORIGINAL_ADMIN_USER:-<none detected>} (kept, auto-login disabled, hidden from picker: $HIDE_ORIGINAL_ACCOUNT)"
  echo "New admin account:      $ADMIN_USERNAME ($ADMIN_FULLNAME)"
  echo "Child accounts:         ${CHILD_USERNAMES[*]}"
  echo "DNS filtering:          Cloudflare for Families (malware + adult content)"
  echo "Browser:                Firefox (.deb, Mozilla repo) with strict site whitelist"
  echo "Whitelisted sites:      ${WHITELIST_SITES_DEFAULT[*]}"
  echo "Daily time limit:       1 hr weekdays / 2 hr weekends, window 6:00 AM-7:00 PM"
  echo "App menu:               Locked to educational whitelist for child accounts"
  echo "Updates:                Unattended security upgrades, auto-reboot overnight"
  echo "Agentic tools:          Claude Code, Codex CLI, OpenCode (npm, admin account)"
  echo "======================================================================"
  read -r -p "Proceed with installation using these settings? [y/N]: " confirm
  [[ "${confirm,,}" == "y" ]] || die "Aborted by user before installation began."

  log "Configuration confirmed. Beginning unattended installation."
}

gather_interrupted_configuration() {
  command -v jq >/dev/null 2>&1 || die "jq is required to resume an interrupted installation."
  INTERRUPTED_INSTALL=true
  ACUKIDS_HOSTNAME=$(jq -er '.hostname' "$INSTALL_STATE_FILE") || die "Invalid interrupted-install state."
  ADMIN_USERNAME=$(jq -er '.admin_account' "$INSTALL_STATE_FILE") || die "Invalid interrupted-install state."
  ORIGINAL_ADMIN_USER=$(jq -r '.original_installer_account // empty' "$INSTALL_STATE_FILE")
  HIDE_ORIGINAL_ACCOUNT=$(jq -r '.hide_original_account // false' "$INSTALL_STATE_FILE")
  mapfile -t CHILD_USERNAMES < <(jq -er '.children[]' "$INSTALL_STATE_FILE") || die "Invalid interrupted-install child state."
  CHILD_PINS=()
  ADMIN_FULLNAME="Existing acuKids administrator"
  ADMIN_PASSWORD=""
  echo "Interrupted acuKids installation detected; resuming with recorded account names."
  [[ "$(jq -r '.admin_existed // false' "$INSTALL_STATE_FILE")" == "true" ]] && die "Interrupted state conflicts with a pre-existing administrator account."
  while IFS= read -r cname; do
    [[ -z "$cname" ]] && continue
    [[ "$(jq -r --arg u "$cname" '.children_existed[$u] // false' "$INSTALL_STATE_FILE")" == "true" ]] && die "Interrupted state conflicts with a pre-existing child account: $cname"
  done <<< "$(printf '%s\n' "${CHILD_USERNAMES[@]}")"
}

write_install_state() {
  install -d -m 0755 "$(dirname "$INSTALL_STATE_FILE")" || die "Could not create installation-state directory."
  local admin_existed=false children_existed='{}' cname
  id "$ADMIN_USERNAME" >/dev/null 2>&1 && admin_existed=true
  for cname in "${CHILD_USERNAMES[@]}"; do id "$cname" >/dev/null 2>&1 && children_existed=$(jq --arg u "$cname" '. + {($u):true}' <<< "$children_existed"); done
  jq -n --arg hostname "$ACUKIDS_HOSTNAME" --arg admin "$ADMIN_USERNAME" \
    --arg original "${ORIGINAL_ADMIN_USER:-}" --argjson hide "${HIDE_ORIGINAL_ACCOUNT:-false}" \
    --argjson children "$(printf '%s\n' "${CHILD_USERNAMES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" \
    --argjson admin_existed "$admin_existed" --argjson children_existed "$children_existed" \
    '{hostname:$hostname,admin_account:$admin,original_installer_account:(if $original == "" then null else $original end),hide_original_account:$hide,children:$children,admin_existed:$admin_existed,children_existed:$children_existed}' > "$INSTALL_STATE_FILE" \
    || die "Could not persist installation state."
  chmod 0644 "$INSTALL_STATE_FILE"
}

# Existing deployments are reconciled from their canonical control repository.
# Do not ask for replacement credentials or rebuild configuration from defaults:
# a rerun is an upgrade/reconciliation operation, not a fresh deployment.
gather_existing_configuration() {
  local meta="$ACUKIDS_HOME/config/system-meta.json"
  local children="$ACUKIDS_HOME/config/children.json"
  [[ -f "$meta" && -f "$children" ]] || die "Existing acuKids deployment is incomplete: expected $meta and $children."
  command -v jq >/dev/null 2>&1 || die "jq is required to reconcile an existing acuKids deployment."

  RERUN_MODE=true
  ACUKIDS_HOSTNAME=$(jq -er '.hostname | strings | select(length > 0)' "$meta") || die "Invalid hostname in $meta."
  ADMIN_USERNAME=$(jq -er '.admin_account | strings | select(length > 0)' "$meta") || die "Invalid admin_account in $meta."
  ORIGINAL_ADMIN_USER=$(jq -r '.original_installer_account // empty' "$meta")
  HIDE_ORIGINAL_ACCOUNT=$(jq -r '.original_installer_account_hidden // false' "$meta")
  local parsed_children
  parsed_children=$(jq -cer 'if (type == "array" and length > 0 and all(.[]; (.username | type == "string"))) then .[].username else error("invalid children array") end' "$children") || die "Invalid child configuration in $children."
  mapfile -t CHILD_USERNAMES <<< "$parsed_children"
  CHILD_PINS=()
  ADMIN_FULLNAME="Existing acuKids administrator"
  ADMIN_PASSWORD=""

  echo "======================================================================"
  echo " Existing acuKids deployment detected"
  echo "======================================================================"
  echo "The existing /opt/acukids configuration is canonical and will be preserved."
  echo "This run will update generated code and reconcile the existing deployment."
  echo "New children and other configuration changes should be made with the"
  echo "generated management tools after this run."
  echo "----------------------------------------------------------------------"
  read -r -p "Proceed with this acuKids reconciliation? [y/N]: " confirm
  [[ "${confirm,,}" == "y" ]] || die "Aborted by user before reconciliation began."
  validate_existing_configuration
  backup_and_migrate_existing_deployment "$meta"
  log "Existing deployment reconciliation confirmed. Canonical configuration will be preserved."
}

validate_existing_configuration() {
  [[ "$RERUN_MODE" == "true" ]] || return 0
  local required
  for required in "$ACUKIDS_HOME/config/children.json" "$ACUKIDS_HOME/config/whitelist-sites.conf" "$ACUKIDS_HOME/config/whitelist-apps.conf" "$ACUKIDS_HOME/config/timekpr-defaults.conf" "$ACUKIDS_HOME/config/dns.conf" "$ACUKIDS_HOME/config/system-meta.json"; do
    [[ -f "$required" ]] || die "Existing acuKids configuration is incomplete: $required"
  done
  jq -e 'type == "array" and length > 0 and all(.[]; .username | type == "string")' "$ACUKIDS_HOME/config/children.json" >/dev/null || die "Existing children.json is invalid."
  jq -e '.admin_account | type == "string"' "$ACUKIDS_HOME/config/system-meta.json" >/dev/null || die "Existing system-meta.json is invalid."
}

backup_and_migrate_existing_deployment() {
  local meta="$1" schema backup
  schema=$(jq -er '.config_schema_version // 1 | numbers' "$meta") || die "Invalid config_schema_version in $meta."
  (( schema <= CONTROL_SCHEMA_VERSION )) || die "Unsupported acuKids config schema version: $schema (maximum supported: $CONTROL_SCHEMA_VERSION)."

  install -d -m 0755 "$RERUN_BACKUP_DIR"
  backup="$RERUN_BACKUP_DIR/rerun-$(date '+%Y%m%d-%H%M%S')-$$.tar.gz"
  tar -czf "$backup" --exclude='acukids/state' -C "$(dirname "$ACUKIDS_HOME")" "$(basename "$ACUKIDS_HOME")" \
    || die "Could not back up the existing acuKids repository to $backup."

  case "$schema" in
    1) log "Existing acuKids configuration schema v1 requires no migration." ;;
    *) die "No migration exists for acuKids config schema version $schema." ;;
  esac
  log "Backed up existing acuKids repository to $backup before reconciliation."
}

# ---------------------------------------------------------------------------
# Step 1: System prep
# ---------------------------------------------------------------------------
step_system_prep() {
  log "=== Step 1: System update & base packages ==="
  hostnamectl set-hostname "$ACUKIDS_HOSTNAME" || die "Failed to set hostname to $ACUKIDS_HOSTNAME."
  sed -i "s/127.0.1.1.*/127.0.1.1\t$ACUKIDS_HOSTNAME/" /etc/hosts 2>/dev/null || \
    echo -e "127.0.1.1\t$ACUKIDS_HOSTNAME" >> /etc/hosts

  export DEBIAN_FRONTEND=noninteractive
  apt-get update >> "$LOG_FILE" 2>&1 || die "apt-get update failed. Check network/log: $LOG_FILE"
  apt-get -y upgrade >> "$LOG_FILE" 2>&1 || die "apt-get upgrade failed. Check network/log: $LOG_FILE"
  install_packages "${BASE_PACKAGES[@]}"
  command -v jq >/dev/null 2>&1 || die "jq is required to generate and apply the acuKids control repository."
  if ! install_branding_assets; then
    OPTIONAL_FAILURES+=("branding")
    log "WARNING: acuKids branding assets could not be installed; deployment will continue with Ubuntu defaults."
  fi
}

# ---------------------------------------------------------------------------
# Step 2: Accounts
# ---------------------------------------------------------------------------
step_accounts() {
  log "=== Step 2: Account setup ==="

  if [[ "$RERUN_MODE" == "true" ]]; then
    getent group "$CHILD_GROUP" >/dev/null || groupadd "$CHILD_GROUP"
    for cname in "${CHILD_USERNAMES[@]}"; do
      id "$cname" >/dev/null 2>&1 || die "Configured child account '$cname' does not exist."
      usermod -aG "$CHILD_GROUP" "$cname" || die "Failed to reconcile '$cname' into child group."
    done
    id "$ADMIN_USERNAME" >/dev/null 2>&1 || die "Configured admin account '$ADMIN_USERNAME' does not exist."
    usermod -aG sudo "$ADMIN_USERNAME" || die "Failed to reconcile sudo membership for '$ADMIN_USERNAME'."
    configure_gdm_login_screen
    log "Reconciled existing acuKids account memberships."
    return
  fi

  # --- Disable auto-login for the original installer account (kept intact) ---
  if [[ -n "${ORIGINAL_ADMIN_USER:-}" ]]; then
    if [[ -f /etc/gdm3/custom.conf ]]; then
      cp /etc/gdm3/custom.conf "/etc/gdm3/custom.conf.acukids-backup"
      sed -i 's/^AutomaticLoginEnable.*/AutomaticLoginEnable=false/' /etc/gdm3/custom.conf
      sed -i "/^AutomaticLogin *=/d" /etc/gdm3/custom.conf
      log "Disabled GDM auto-login (if it was enabled)."
    fi
    log "Original installer account '$ORIGINAL_ADMIN_USER' retained as fallback login."

    if [[ "$HIDE_ORIGINAL_ACCOUNT" == "true" ]]; then
      install -d /var/lib/AccountsService/users
      local f="/var/lib/AccountsService/users/$ORIGINAL_ADMIN_USER"
      if [[ -f "$f" ]]; then
        if grep -q "^SystemAccount=" "$f"; then
          sed -i "s/^SystemAccount=.*/SystemAccount=true/" "$f"
        elif grep -q "^\[User\]" "$f"; then
          sed -i "/^\[User\]/a SystemAccount=true" "$f"
        else
          printf '[User]\nSystemAccount=true\n' >> "$f"
        fi
      else
        printf '[User]\nSystemAccount=true\n' > "$f"
      fi
      systemctl restart accounts-daemon >> "$LOG_FILE" 2>&1 || true
      log "Hid '$ORIGINAL_ADMIN_USER' from the login picker (still usable by typing the username manually)."
    fi
  fi

  # --- Create new admin account ---
  if [[ "$INTERRUPTED_INSTALL" == "true" ]] && id "$ADMIN_USERNAME" &>/dev/null; then
    usermod -aG sudo "$ADMIN_USERNAME" || die "Failed to reconcile admin account '$ADMIN_USERNAME'."
  elif id "$ADMIN_USERNAME" &>/dev/null; then
    die "Admin username '$ADMIN_USERNAME' already belongs to an existing account. Choose a different username."
  else
    adduser --disabled-password --gecos "$ADMIN_FULLNAME" "$ADMIN_USERNAME" >> "$LOG_FILE" 2>&1 || die "Failed to create admin account '$ADMIN_USERNAME'."
    usermod -aG sudo "$ADMIN_USERNAME" || die "Failed to grant sudo membership to '$ADMIN_USERNAME'."
    echo "${ADMIN_USERNAME}:${ADMIN_PASSWORD}" | chpasswd || die "Failed to set the admin password."
    log "Created admin account: $ADMIN_USERNAME (sudo)"
  fi
  unset ADMIN_PASSWORD ADMIN_PASSWORD_CONFIRM

  # --- Create child group ---
  getent group "$CHILD_GROUP" >/dev/null || groupadd "$CHILD_GROUP" || die "Failed to create child group '$CHILD_GROUP'."

  # --- Create child accounts ---
  for idx in "${!CHILD_USERNAMES[@]}"; do
    cname="${CHILD_USERNAMES[$idx]}"
    # Interrupted-install state deliberately never stores PINs. Accounts
    # created before a failure already have their PIN, so resume must retain
    # it rather than expanding an unset array under `set -u`.
    cpin="${CHILD_PINS[$idx]:-}"
    if id "$cname" &>/dev/null; then
      if ! getent group "$CHILD_GROUP" | grep -qw -- "$cname"; then
        die "Child username '$cname' belongs to an existing account that is not acuKids-managed. Choose a different username."
      fi
      log "Child user $cname is already acuKids-managed; reconciling membership and PIN."
      usermod -aG "$CHILD_GROUP" "$cname" || die "Failed to reconcile '$cname' into child group."
    else
      adduser --disabled-password --gecos "$cname" "$cname" >> "$LOG_FILE" 2>&1 || die "Failed to create child account '$cname'."
      usermod -aG "$CHILD_GROUP" "$cname" || die "Failed to add '$cname' to child group."
      log "Created child account: $cname"
    fi
    if [[ -n "$cpin" ]]; then
      echo "${cname}:${cpin}" | chpasswd || die "Failed to set the PIN for child '$cname'."
    elif [[ "$INTERRUPTED_INSTALL" == "true" ]]; then
      log "Retaining existing PIN for resumed child account '$cname'."
    else
      die "Missing PIN for child '$cname'."
    fi
  done
  unset CHILD_PINS

  # --- GDM: show the user list so children can click their name ---
  configure_gdm_login_screen
}

configure_gdm_login_screen() {
  # GDM daemon settings belong in custom.conf; login-screen dconf keys do not.
  # Remove the invalid section written by older acuKids versions if present.
  if [[ -f /etc/gdm3/custom.conf ]]; then
    sed -i '/^\[org\.gnome\.login-screen\]$/,/^disable-user-list=false$/d' /etc/gdm3/custom.conf || die "Could not remove obsolete GDM login-screen configuration."
  fi
  install -d /etc/dconf/profile /etc/dconf/db/gdm.d || die "Could not create the GDM dconf database directory."
  if [[ ! -f /etc/dconf/profile/gdm ]]; then
    cat > /etc/dconf/profile/gdm << 'GDM_PROFILE_EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
GDM_PROFILE_EOF
    chmod 0644 /etc/dconf/profile/gdm || die "Could not install the GDM dconf profile."
  elif ! grep -qx 'system-db:gdm' /etc/dconf/profile/gdm; then
    cp /etc/dconf/profile/gdm /etc/dconf/profile/gdm.acukids-backup || die "Could not back up the existing GDM dconf profile."
    printf '\nsystem-db:gdm\n' >> /etc/dconf/profile/gdm || die "Could not add the acuKids GDM dconf database."
  fi
  local staged
  staged=$(mktemp /etc/dconf/db/gdm.d/.acukids-login-screen.XXXXXX) || die "Could not stage GDM login-screen configuration."
  cat > "$staged" << 'GDM_DCONF_EOF'
[org/gnome/login-screen]
disable-user-list=false
GDM_DCONF_EOF
  if [[ -f "$BRANDING_DIR/acukids-login-logo.svg" ]]; then
    printf "logo='%s'\nfallback-logo='%s'\n" \
      "$BRANDING_DIR/acukids-login-logo.svg" \
      "$BRANDING_DIR/acukids-login-logo.svg" >> "$staged"
  fi
  chmod 0644 "$staged" && mv -f "$staged" /etc/dconf/db/gdm.d/00-acukids-login-screen || { rm -f "$staged"; die "Could not install GDM login-screen configuration."; }
  dconf update || die "Could not compile the GDM dconf database."
}

# ---------------------------------------------------------------------------
# Step 3: Educational software
# ---------------------------------------------------------------------------
step_edu_software() {
  log "=== Step 3: Educational software ==="
  install_packages "${EDU_PACKAGES[@]}"
  install_child_logout_launcher
  discover_app_desktop_files
}

# A visible, child-friendly way to finish a session. GNOME's normal
# confirmation prompt remains enabled so an accidental click is recoverable.
install_child_logout_launcher() {
  local staged
  install -d -m 0755 /usr/share/applications || die "Could not create the applications directory."
  staged=$(mktemp /usr/share/applications/.acukids-done.XXXXXX) || die "Could not stage the child logout launcher."
  cat > "$staged" << 'DONE_DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=I'm all done
Comment=Log out of acuKids
Exec=/usr/bin/gnome-session-quit --logout
Icon=system-log-out
Terminal=false
Categories=Utility;
DONE_DESKTOP_EOF
  chmod 0644 "$staged" && mv -f "$staged" /usr/share/applications/acukids-done.desktop || { rm -f "$staged"; die "Could not install the child logout launcher."; }
}

# Instead of trusting hardcoded .desktop filenames (which have already
# broken once when a package switched to a reverse-DNS-style name), this
# inspects what each installed package actually shipped via `dpkg -L` and
# builds the real whitelist from that. This keeps the app lockdown correct
# even if upstream renames a .desktop file again in a future release.
APP_DISCOVERY_PACKAGES=(gcompris-qt tuxpaint tuxmath tuxtype krita audacity stellarium)

discover_app_desktop_files() {
  WHITELIST_APPS_RUNTIME=()
  for pkg in "${APP_DISCOVERY_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      local found=0
      while IFS= read -r df; do
        WHITELIST_APPS_RUNTIME+=("$(basename "$df")")
        found=1
      done < <(dpkg -L "$pkg" 2>/dev/null | grep -E '/applications/.*\.desktop$')
      [[ $found -eq 1 ]] || log "NOTE: package '$pkg' installed but shipped no .desktop file found via dpkg -L."
    else
      log "NOTE: package '$pkg' is not installed; its app will not appear on the kids' whitelist."
    fi
  done

  # Always include these regardless of the edu-package discovery above.
  WHITELIST_APPS_RUNTIME+=(
    "firefox.desktop"
    "org.gnome.Firefox.desktop"
    "org.gnome.Nautilus.desktop"
    "org.gnome.font-viewer.desktop"
    "simple-scan.desktop"
    "acukids-done.desktop"
  )

  # If discovery somehow found nothing at all, fall back to the static list
  # rather than shipping an empty (fully-blank) app grid.
  if [[ ${#WHITELIST_APPS_RUNTIME[@]} -eq 0 ]]; then
    log "WARNING: app discovery found nothing; falling back to static whitelist defaults."
    WHITELIST_APPS_RUNTIME=("${WHITELIST_APPS_DEFAULT[@]}")
  fi

  log "Discovered whitelist apps: ${WHITELIST_APPS_RUNTIME[*]}"
}

# ---------------------------------------------------------------------------
# Step 4: Browsers - Firefox (deb, locked down for kids) + Chromium (admin)
# ---------------------------------------------------------------------------
step_browsers() {
  log "=== Step 4: Browser setup ==="

  # --- Add Mozilla's official APT repo ---
  install -d -m 0755 /etc/apt/keyrings
  wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O /etc/apt/keyrings/packages.mozilla.org.asc \
    || die "Failed to fetch Mozilla APT signing key."
  gpg --batch --quiet --show-keys /etc/apt/keyrings/packages.mozilla.org.asc >> "$LOG_FILE" 2>&1 \
    || die "Downloaded Mozilla APT signing key is invalid or unverifiable."
  expected_mozilla_fingerprint="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
  actual_mozilla_fingerprint=$(gpg --batch --with-colons --show-keys /etc/apt/keyrings/packages.mozilla.org.asc | awk -F: '$1 == "fpr" { print $10; exit }')
  [[ "$actual_mozilla_fingerprint" == "$expected_mozilla_fingerprint" ]] || die "Mozilla APT signing key fingerprint did not match the expected value."
  cat > /etc/apt/sources.list.d/mozilla.sources << 'MOZ_SOURCES'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
MOZ_SOURCES
  [[ -s /etc/apt/sources.list.d/mozilla.sources ]] || die "Failed to write Mozilla APT source configuration."

  # Pin: prefer Mozilla's firefox package strongly over any Ubuntu-archive
  # package of the same name (which is just a snap wrapper), and prevent
  # apt/unattended-upgrades from silently reinstalling the snap wrapper.
  cat > /etc/apt/preferences.d/mozilla-firefox << 'MOZ_PIN'
Package: firefox*
Pin: origin packages.mozilla.org
Pin-Priority: 1001

Package: firefox*
Pin: release o=Ubuntu
Pin-Priority: -1
MOZ_PIN
  [[ -s /etc/apt/preferences.d/mozilla-firefox ]] || die "Failed to write Firefox apt pinning policy."

  apt-get update >> "$LOG_FILE" 2>&1 || die "apt-get update failed while configuring Firefox. Check log: $LOG_FILE"
  # Ubuntu's preinstalled snap transition package has an epoch (1:...), while
  # Mozilla's native package does not. APT therefore describes this intentional
  # replacement as a downgrade even though the Firefox release is newer. Allow
  # that specific transition; do not broaden this flag to every package install.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    --allow-downgrades firefox >> "$LOG_FILE" 2>&1 \
    || die "Firefox package installation failed; check $LOG_FILE for the APT error."
  dpkg -s firefox >/dev/null 2>&1 || die "Firefox package installation failed; child browser lockdown cannot be provided."
  # Avoid `apt-cache ... | grep -q` here: with pipefail enabled, grep's early
  # exit can SIGPIPE apt-cache and falsely report a repository failure.
  firefox_policy=$(apt-cache policy firefox 2>/dev/null) || die "Could not inspect Firefox package origin."
  grep -q 'packages.mozilla.org' <<< "$firefox_policy" || die "Firefox was not installed from Mozilla's repository."
  # Remove the snap only after the replacement package is installed and its
  # repository origin has been verified, preserving a working browser on error.
  snap remove firefox >> "$LOG_FILE" 2>&1 || true
  if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
    die "Firefox snap is still installed; refusing to continue with mixed browser origins."
  fi

  # --- Chromium (snap, default/unrestricted) reserved for the admin account ---
  if ! snap list chromium &>/dev/null; then
    snap install chromium >> "$LOG_FILE" 2>&1 || { log "WARNING: chromium snap install failed, admin will need to install a browser manually."; OPTIONAL_FAILURES+=("browser:chromium"); }
  fi

  # --- Firefox enterprise policy: strict whitelist + lockdown ---
  install -d -m 0755 /etc/firefox/policies
  local staged_policy
  staged_policy=$(mktemp /etc/firefox/policies/.acukids-policy.XXXXXX) || die "Failed to stage Firefox policy."
  generate_firefox_policy > "$staged_policy" || { rm -f "$staged_policy"; die "Failed to generate Firefox policy."; }
  jq empty "$staged_policy" >/dev/null 2>&1 || { rm -f "$staged_policy"; die "Generated Firefox policy is invalid JSON."; }
  chmod 0644 "$staged_policy" && mv -f "$staged_policy" /etc/firefox/policies/policies.json || { rm -f "$staged_policy"; die "Failed to install Firefox policy."; }
  log "Firefox policies written to /etc/firefox/policies/policies.json"
}

# Generates policies.json from the current whitelist array. Also called by
# acukids-apply.sh (via a copy of this function) when the whitelist changes.
generate_firefox_policy() {
  local sites_json
  # Build a clean JSON array of allowed URL patterns. This must include the
  # local homepage file, not just the approved external sites - the
  # WebsiteFilter "Block": ["<all_urls>"] pattern matches every URL scheme,
  # including file://, so without an explicit exception here Firefox blocks
  # its own homepage on startup.
  sites_json="[\"file:///opt/acukids/homepage/*\""
  for s in "${WHITELIST_SITES_RUNTIME[@]:-${WHITELIST_SITES_DEFAULT[@]}}"; do
    sites_json+=",\"*://*.${s}/*\",\"*://${s}/*\""
  done
  sites_json+="]"

  cat << POLICY_EOF
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableDeveloperTools": true,
    "DisableFirefoxAccounts": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableSetDesktopBackground": true,
    "DisableSecurityBypass": {
      "InvalidCertificate": true,
      "SafeBrowsing": true
    },
    "DisablePrivateBrowsing": true,
    "DisableFormHistory": false,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true,
    "OfferToSaveLogins": false,
    "PasswordManagerEnabled": false,
    "PopupBlocking": { "Default": true, "Locked": true },
    "HardwareAcceleration": true,
    "Homepage": {
      "URL": "file:///opt/acukids/homepage/index.html",
      "Locked": true,
      "StartPage": "homepage"
    },
    "OverrideFirstRunPage": "file:///opt/acukids/homepage/index.html",
    "NewTabPage": false,
    "BlockAboutConfig": true,
    "BlockAboutAddons": true,
    "BlockAboutProfiles": true,
    "BlockAboutSupport": true,
    "Extensions": {
      "Install": [],
      "Uninstall": [],
      "Locked": []
    },
    "InstallAddonsPermission": {
      "Default": false
    },
    "WebsiteFilter": {
      "Block": ["<all_urls>"],
      "Exceptions": ${sites_json}
    }
  }
}
POLICY_EOF
}

# ---------------------------------------------------------------------------
# Step 5: DNS filtering - Cloudflare for Families (malware + adult content)
# ---------------------------------------------------------------------------
step_dns_filtering() {
  log "=== Step 5: DNS filtering (Cloudflare for Families) ==="
  # Cloudflare for Families - "No Malware or Adult Content" resolvers:
  #   1.1.1.3 / 1.0.0.3   (IPv4)
  #   2606:4700:4700::1113 / 2606:4700:4700::1003 (IPv6)
  mkdir -p /etc/systemd/resolved.conf.d || die "Failed to create systemd-resolved configuration directory."
  local staged_dns
  staged_dns=$(mktemp /etc/systemd/resolved.conf.d/.acukids-dns.XXXXXX) || die "Failed to stage acuKids DNS configuration."
  cat > "$staged_dns" << 'DNS_EOF'
[Resolve]
DNS=1.1.1.3 1.0.0.3 2606:4700:4700::1113 2606:4700:4700::1003
FallbackDNS=1.1.1.3 1.0.0.3
DNSOverTLS=opportunistic
DNS_EOF
  chmod 0644 "$staged_dns" && mv -f "$staged_dns" /etc/systemd/resolved.conf.d/acukids-dns.conf || { rm -f "$staged_dns"; die "Failed to install acuKids DNS configuration."; }

  # Also pin NetworkManager connections to use these DNS servers directly and
  # ignore DHCP-provided DNS, so filtering can't be bypassed by network change.
  if command -v nmcli &>/dev/null; then
    connection_profiles=$(nmcli -t -f UUID,TYPE connection show 2>>"$LOG_FILE") || die "Could not enumerate NetworkManager connections."
    while IFS=: read -r uuid connection_type || [[ -n "$uuid" ]]; do
      [[ -z "$uuid" ]] && continue
      [[ "$connection_type" == loopback ]] && continue
      local ipv4_method ipv6_method
      ipv4_method=$(nmcli -g ipv4.method connection show uuid "$uuid" 2>/dev/null || true)
      ipv6_method=$(nmcli -g ipv6.method connection show uuid "$uuid" 2>/dev/null || true)
      if [[ "$ipv4_method" != link-local && "$ipv4_method" != disabled && -n "$ipv4_method" ]]; then
        nmcli connection modify uuid "$uuid" ipv4.dns "1.1.1.3 1.0.0.3" ipv4.ignore-auto-dns yes >> "$LOG_FILE" 2>&1 || die "Could not apply IPv4 DNS settings to NetworkManager connection '$uuid'."
      else
        log "Skipping IPv4 DNS pinning for connection '$uuid' (method=${ipv4_method:-unknown} does not accept DNS settings)."
      fi
      if [[ "$ipv6_method" != link-local && "$ipv6_method" != ignore && "$ipv6_method" != disabled && -n "$ipv6_method" ]]; then
        nmcli connection modify uuid "$uuid" ipv6.dns "2606:4700:4700::1113 2606:4700:4700::1003" ipv6.ignore-auto-dns yes >> "$LOG_FILE" 2>&1 || die "Could not apply IPv6 DNS settings to NetworkManager connection '$uuid'."
      fi
    done <<< "$connection_profiles"
    install -d /etc/NetworkManager/dispatcher.d || die "Could not create NetworkManager dispatcher directory."
    local staged_dispatcher
    staged_dispatcher=$(mktemp /etc/NetworkManager/dispatcher.d/.acukids-dns.XXXXXX) || die "Could not stage NetworkManager DNS dispatcher."
    cat > "$staged_dispatcher" << 'DISPATCHER_EOF'
#!/bin/sh
[ "${2:-}" = up ] || exit 0
[ -n "${CONNECTION_UUID:-}" ] || exit 0
nmcli connection modify uuid "$CONNECTION_UUID" \
  ipv4.dns "1.1.1.3 1.0.0.3" ipv4.ignore-auto-dns yes \
  ipv6.dns "2606:4700:4700::1113 2606:4700:4700::1003" ipv6.ignore-auto-dns yes 2>/dev/null || true
DISPATCHER_EOF
    chmod 0755 "$staged_dispatcher" && mv -f "$staged_dispatcher" /etc/NetworkManager/dispatcher.d/99-acukids-dns || { rm -f "$staged_dispatcher"; die "Could not install NetworkManager DNS dispatcher."; }
  fi

  systemctl restart systemd-resolved >> "$LOG_FILE" 2>&1 || die "Failed to restart systemd-resolved after configuring DNS."
  resolvectl dns >/dev/null 2>&1 || die "Could not verify active systemd-resolved DNS state."
  log "DNS filtering configured (Cloudflare for Families: 1.1.1.3 / 1.0.0.3)."
}

# ---------------------------------------------------------------------------
# Step 6: timekpr-next daily time limits
# ---------------------------------------------------------------------------
install_timekpr_package() {
  command -v add-apt-repository >/dev/null 2>&1 || die "add-apt-repository is required to install the supported timekpr-next package."
  add-apt-repository -y "$TIMEKPR_PPA" >> "$LOG_FILE" 2>&1 || die "Failed to add the timekpr-next repository ($TIMEKPR_PPA)."
  apt-get update >> "$LOG_FILE" 2>&1 || die "Failed to update package lists after adding the timekpr-next repository."
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends timekpr-next >> "$LOG_FILE" 2>&1 \
    || die "Failed to install timekpr-next from $TIMEKPR_PPA."

  TIMEKPR_INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' timekpr-next 2>/dev/null) || die "Could not determine the installed timekpr-next version."
  dpkg --compare-versions "$TIMEKPR_INSTALLED_VERSION" ge "$TIMEKPR_MIN_VERSION" \
    || die "timekpr-next $TIMEKPR_INSTALLED_VERSION is unsupported; acuKids requires $TIMEKPR_MIN_VERSION or newer."
  local policy
  policy=$(apt-cache policy timekpr-next 2>/dev/null) || die "Could not inspect the installed timekpr-next package origin."
  grep -q 'ppa.launchpadcontent.net/mjasnik/ppa' <<< "$policy" \
    || die "timekpr-next was not installed from the supported upstream PPA."
  for launcher in /usr/bin/timekprd /usr/bin/timekpra /usr/bin/timekprc; do
    [[ -s "$launcher" && $(wc -c < "$launcher") -gt 20 ]] \
      || die "Installed timekpr-next launcher is unusable: $launcher"
  done
  systemctl enable --now timekpr.service >> "$LOG_FILE" 2>&1 || die "Failed to start timekpr service."
  sleep 2
  systemctl is-active --quiet timekpr.service || die "timekpr service is not active after installation; check $LOG_FILE."
  local cli_help
  cli_help=$(timekpra --help 2>&1) || die "timekpra is not functional after installing timekpr-next $TIMEKPR_INSTALLED_VERSION."
  [[ -n "$cli_help" ]] || die "timekpra returned no help output; the installed timekpr package is unusable."
  log "Installed and verified timekpr-next $TIMEKPR_INSTALLED_VERSION from $TIMEKPR_PPA."
}

step_time_limits() {
  log "=== Step 6: Time limit configuration (timekpr-next) ==="
  install_timekpr_package

  for cname in "${CHILD_USERNAMES[@]}"; do
    configure_child_time_limits "$cname"
  done
}

# Applies the acuKids default schedule to one username via timekpra CLI.
# Weekday (Mon-Fri) = 1 hour/day, Weekend (Sat-Sun) = 2 hours/day
# Allowed window every day: 06:00-19:00
configure_child_time_limits() {
  local cname="$1"
  if ! command -v timekpra &>/dev/null; then
    die "timekpra is not available; cannot configure time limits for $cname."
  fi
  # Days: 1=Mon ... 7=Sun. Limits in seconds.
  timekpra --settimelimits "$cname" "3600;3600;3600;3600;3600;7200;7200" >> "$LOG_FILE" 2>&1 || die "Failed to set time limits for $cname."
  # Allowed hours each day: 06:00-19:00 -> hours 6 through 18.
  timekpra --setalloweddays "$cname" "1;2;3;4;5;6;7" >> "$LOG_FILE" 2>&1 || die "Failed to set allowed days for $cname."
  timekpra --setallowedhours "$cname" "ALL" "6;7;8;9;10;11;12;13;14;15;16;17;18" >> "$LOG_FILE" 2>&1 || die "Failed to set allowed hours for $cname."
  timekpra --setlockouttype "$cname" "lock" >> "$LOG_FILE" 2>&1 || die "Failed to set lockout type for $cname."
  log "Time limits applied for $cname: 1h weekdays / 2h weekends, 6:00 AM-7:00 PM window."
}


# ---------------------------------------------------------------------------
# Step 7: Desktop / app lockdown for child accounts (dconf + hidden apps)
# ---------------------------------------------------------------------------
step_desktop_lockdown() {
  log "=== Step 7: Desktop lockdown for child accounts ==="

  # --- dconf profile + mandatory settings db for children ---
  install -d /etc/dconf/profile /etc/dconf/db/${DCONF_PROFILE_NAME}.d || die "Failed to create dconf configuration directories."
  local staged_dconf_profile
  staged_dconf_profile=$(mktemp /etc/dconf/profile/.acukids-profile.XXXXXX) || die "Failed to stage child dconf profile."
  cat > "$staged_dconf_profile" << PROFILE_EOF
user-db:user
system-db:${DCONF_PROFILE_NAME}
PROFILE_EOF
  chmod 0644 "$staged_dconf_profile" && mv -f "$staged_dconf_profile" /etc/dconf/profile/${DCONF_PROFILE_NAME} || { rm -f "$staged_dconf_profile"; die "Failed to install the child dconf profile."; }

  local staged_lockdown
  staged_lockdown=$(mktemp /etc/dconf/db/${DCONF_PROFILE_NAME}.d/.acukids-lockdown.XXXXXX) || die "Failed to stage dconf lockdown settings."
  cat > "$staged_lockdown" << 'LOCKDOWN_EOF'
[org/gnome/desktop/lockdown]
disable-command-line=true
disable-user-switching=false
disable-log-out=false
disable-lock-screen=false
disable-printing=false
disable-print-setup=false
user-administration-disabled=true

[org/gnome/desktop/background]
show-desktop-icons=false

[org/gnome/nautilus/preferences]
show-create-link=false

[org/gnome/shell]
disable-user-extensions=true

[org/gnome/desktop/media-handling]
autorun-never=true

[org/gnome/settings-daemon/plugins/media-keys]
terminal=@as []
LOCKDOWN_EOF
  chmod 0644 "$staged_lockdown" && mv -f "$staged_lockdown" /etc/dconf/db/${DCONF_PROFILE_NAME}.d/00-lockdown || { rm -f "$staged_lockdown"; die "Failed to install dconf lockdown settings."; }

  # Keep the dock simple and predictable for young children. Favorites use
  # the real desktop filenames discovered above, preserving each app's name
  # and icon rather than introducing a second labeling system.
  local staged_child_ui favorites app
  staged_child_ui=$(mktemp /etc/dconf/db/${DCONF_PROFILE_NAME}.d/.acukids-child-ui.XXXXXX) || die "Failed to stage child desktop settings."
  favorites=""
  for app in "${WHITELIST_APPS_RUNTIME[@]}"; do
    # Files and Font Viewer remain available from the app grid, but are not
    # everyday child activities and therefore do not occupy dock space.
    case "$app" in
      org.gnome.Nautilus.desktop|org.gnome.font-viewer.desktop) continue ;;
    esac
    [[ -n "$favorites" ]] && favorites+=","
    favorites+="'$app'"
  done
  cat > "$staged_child_ui" << CHILD_UI_EOF
[org/gnome/shell]
favorite-apps=[$favorites]

[org/gnome/shell/extensions/dash-to-dock]
dock-position='BOTTOM'
dock-fixed=true
autohide=false
intellihide=false
dash-max-icon-size=56
show-mounts=false
show-trash=false
show-show-apps-button=true
show-apps-at-top=false

[org/gnome/shell/extensions/ding]
show-home=false
show-trash=false
show-volumes=false
show-network-volumes=false
CHILD_UI_EOF
  chmod 0644 "$staged_child_ui" && mv -f "$staged_child_ui" /etc/dconf/db/${DCONF_PROFILE_NAME}.d/02-child-ui || { rm -f "$staged_child_ui"; die "Failed to install child desktop settings."; }

  install -d /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks || die "Failed to create dconf lock directory."
  local staged_locks
  staged_locks=$(mktemp /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/.acukids-locks.XXXXXX) || die "Failed to stage dconf lockdown locks."
  cat > "$staged_locks" << 'LOCKS_EOF'
/org/gnome/desktop/lockdown/disable-command-line
/org/gnome/desktop/lockdown/user-administration-disabled
/org/gnome/shell/disable-user-extensions
LOCKS_EOF
  chmod 0644 "$staged_locks" && mv -f "$staged_locks" /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/00-lockdown-locks || { rm -f "$staged_locks"; die "Failed to install dconf lockdown locks."; }
  cat > /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/02-child-ui-locks << 'CHILD_UI_LOCKS_EOF'
/org/gnome/shell/favorite-apps
/org/gnome/shell/extensions/dash-to-dock/dock-position
/org/gnome/shell/extensions/dash-to-dock/dock-fixed
/org/gnome/shell/extensions/dash-to-dock/autohide
/org/gnome/shell/extensions/dash-to-dock/intellihide
/org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size
/org/gnome/shell/extensions/dash-to-dock/show-mounts
/org/gnome/shell/extensions/dash-to-dock/show-trash
/org/gnome/shell/extensions/dash-to-dock/show-show-apps-button
/org/gnome/shell/extensions/dash-to-dock/show-apps-at-top
/org/gnome/shell/extensions/ding/show-home
/org/gnome/shell/extensions/ding/show-trash
/org/gnome/shell/extensions/ding/show-volumes
/org/gnome/shell/extensions/ding/show-network-volumes
CHILD_UI_LOCKS_EOF
  chmod 0644 /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/02-child-ui-locks || die "Failed to protect child desktop settings."

  if [[ -f "$BRANDING_DIR/acukids-wallpaper.png" ]]; then
    cat > /etc/dconf/db/${DCONF_PROFILE_NAME}.d/01-branding << 'BRANDING_DCONF_EOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/acukids/branding/acukids-wallpaper.png'
picture-uri-dark='file:///usr/share/acukids/branding/acukids-wallpaper.png'
picture-options='zoom'
BRANDING_DCONF_EOF
    cat > /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/01-branding-locks << 'BRANDING_LOCKS_EOF'
/org/gnome/desktop/background/picture-uri
/org/gnome/desktop/background/picture-uri-dark
/org/gnome/desktop/background/picture-options
BRANDING_LOCKS_EOF
    chmod 0644 /etc/dconf/db/${DCONF_PROFILE_NAME}.d/01-branding \
      /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/01-branding-locks || die "Failed to protect child wallpaper settings."
  else
    rm -f /etc/dconf/db/${DCONF_PROFILE_NAME}.d/01-branding \
      /etc/dconf/db/${DCONF_PROFILE_NAME}.d/locks/01-branding-locks
  fi

  # --- Assign the child dconf profile only to child-group members ---
  local staged_profile_env
  staged_profile_env=$(mktemp /etc/profile.d/.acukids-dconf.XXXXXX) || die "Failed to stage child dconf session profile."
  cat > "$staged_profile_env" << PROFILE_ENV_EOF
#!/bin/sh
# Applies the acuKids locked-down dconf profile to child accounts only.
if getent group ${CHILD_GROUP} | grep -q "\\b\${USER}\\b"; then
  export DCONF_PROFILE=${DCONF_PROFILE_NAME}
fi
PROFILE_ENV_EOF
  chmod 0644 "$staged_profile_env" && mv -f "$staged_profile_env" /etc/profile.d/acukids-dconf.sh || { rm -f "$staged_profile_env"; die "Failed to install child dconf session profile."; }

  dconf update || die "Failed to compile the child dconf database."

  for cname in "${CHILD_USERNAMES[@]}"; do
    prepare_child_user_dirs "$cname"
    configure_child_dconf_environment "$cname"
  done

  # --- Hide non-whitelisted applications from each child's app grid ---
  for cname in "${CHILD_USERNAMES[@]}"; do
    apply_app_whitelist_to_user "$cname" || die "Failed to apply application whitelist for child '$cname'."
  done

  # --- Disable Nautilus "Open Terminal Here" and hide the Software/Terminal apps ---
  for app in org.gnome.Terminal.desktop gnome-terminal.desktop org.gnome.Software.desktop snap-store_ui.desktop update-manager.desktop gnome-control-center.desktop; do
    install -d -m 0755 /usr/share/applications
    if [[ -f "/usr/share/applications/$app" ]]; then
      for cname in "${CHILD_USERNAMES[@]}"; do
        home=$(getent passwd "$cname" | cut -d: -f6) || die "Could not resolve home directory for child '$cname'."
        [[ -n "$home" && -d "$home" ]] || die "Configured child '$cname' has no usable home directory."
        install -d -m 0755 "$home/.local/share/applications" || die "Failed to create child application override directory."
        local staged_hide
        staged_hide=$(mktemp "$home/.local/share/applications/.acukids-hide.XXXXXX") || die "Failed to stage hidden application override for '$app'."
        cat > "$staged_hide" << HIDE_EOF
[Desktop Entry]
Type=Application
Name=Hidden
NoDisplay=true
HIDE_EOF
        chmod 0644 "$staged_hide" && mv -f "$staged_hide" "$home/.local/share/applications/$app" || { rm -f "$staged_hide"; die "Failed to install hidden application override for '$app'."; }
        chown "$cname:$cname" "$home/.local/share/applications/$app" || die "Failed to install hidden application override for '$app'."
      done
    fi
  done
}

prepare_child_user_dirs() {
  local cname="$1" home
  home=$(getent passwd "$cname" | cut -d: -f6) || die "Could not resolve home directory for child '$cname'."
  [[ -n "$home" && -d "$home" ]] || die "Configured child '$cname' has no usable home directory."
  install -d -m 0755 "$home/.config" "$home/.config/environment.d" "$home/.local" "$home/.local/share" "$home/.local/share/applications" "$home/.local/share/keyrings" || die "Could not create per-user directories for '$cname'."
  chown "$cname:$cname" "$home/.config" "$home/.config/environment.d" "$home/.local" "$home/.local/share" "$home/.local/share/applications" "$home/.local/share/keyrings" || die "Could not set per-user directory ownership for '$cname'."
  # Skip Ubuntu/GNOME's first-login onboarding; acuKids provisions the child
  # account and desktop policy non-interactively during deployment.
  touch "$home/.config/gnome-initial-setup-done" || die "Could not mark GNOME initial setup complete for '$cname'."
  chown "$cname:$cname" "$home/.config/gnome-initial-setup-done" || die "Could not set GNOME setup marker ownership for '$cname'."
}

configure_child_dconf_environment() {
  local cname="$1" home staged
  home=$(getent passwd "$cname" | cut -d: -f6) || die "Could not resolve home directory for child '$cname'."
  [[ -n "$home" && -d "$home" ]] || die "Configured child '$cname' has no usable home directory."
  install -d -m 0755 "$home/.config/environment.d" || die "Could not create dconf environment directory for '$cname'."
  staged=$(mktemp "$home/.config/environment.d/.acukids-dconf.XXXXXX") || die "Could not stage dconf environment for '$cname'."
  printf 'DCONF_PROFILE=%s\n' "$DCONF_PROFILE_NAME" > "$staged"
  chmod 0644 "$staged" && mv -f "$staged" "$home/.config/environment.d/90-acukids-dconf.conf" || { rm -f "$staged"; die "Could not install dconf environment for '$cname'."; }
  chown "$cname:$cname" "$home/.config/environment.d/90-acukids-dconf.conf" || die "Could not set dconf environment ownership for '$cname'."
}

# Hides every installed .desktop entry EXCEPT the acuKids whitelist for one
# child account, by writing NoDisplay=true overrides into that user's
# ~/.local/share/applications (which takes precedence over the system copy).
apply_app_whitelist_to_user() {
  local cname="$1"
  local home
  home=$(getent passwd "$cname" | cut -d: -f6) || return 1
  [[ -n "$home" && -d "$home" ]] || return 1
  install -d -m 0755 "$home/.local/share/applications" || return 1

  local whitelist=("${WHITELIST_APPS_RUNTIME[@]:-${WHITELIST_APPS_DEFAULT[@]}}")
  local blacklist_file="$ACUKIDS_HOME/config/blacklist-apps.conf"
  if [[ -f "$blacklist_file" ]]; then
    local app filtered=()
    while IFS= read -r app; do
      [[ -z "$app" || "$app" == \#* ]] && continue
      filtered+=("$app")
    done < "$blacklist_file"
    local kept=()
    for app in "${whitelist[@]}"; do
      local blocked=0 b
      for b in "${filtered[@]}"; do [[ "$app" == "$b" ]] && blocked=1 && break; done
      (( blocked == 0 )) && kept+=("$app")
    done
    whitelist=("${kept[@]}")
  fi

  # Clear any previously-written hide-overrides first. Without this, an app
  # that used to be (wrongly) hidden - e.g. because an earlier run guessed
  # its .desktop filename incorrectly - would stay hidden forever even
  # after the whitelist is corrected, since this loop only ever ADDS
  # overrides for apps that are currently unapproved; it never removes one
  # for an app that has since become approved. Wiping and regenerating
  # from scratch every time keeps this function safely re-runnable.
  find "$home/.local/share/applications" -maxdepth 1 -name '*.desktop' -delete 2>/dev/null || return 1

  shopt -s nullglob
  for desktop_file in /usr/share/applications/*.desktop /var/lib/snapd/desktop/applications/*.desktop; do
    local base
    base=$(basename "$desktop_file")
    local keep=0
    for w in "${whitelist[@]}"; do
      [[ "$base" == "$w" ]] && keep=1 && break
    done
    if [[ $keep -eq 0 ]]; then
      cat > "$home/.local/share/applications/$base" << HIDE_EOF
[Desktop Entry]
Type=Application
Name=Hidden
NoDisplay=true
HIDE_EOF
      [[ -s "$home/.local/share/applications/$base" ]] || return 1
    fi
  done
  shopt -u nullglob

  chown -R "$cname:$cname" "$home/.local/share/applications" || return 1
  log "Applied app whitelist lockdown for $cname."
}

# ---------------------------------------------------------------------------
# Step 8: Unattended security upgrades
# ---------------------------------------------------------------------------
step_unattended_upgrades() {
  log "=== Step 8: Unattended upgrades ==="
  cat > /etc/apt/apt.conf.d/50unattended-upgrades-acukids << 'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
UU_EOF
  [[ -s /etc/apt/apt.conf.d/50unattended-upgrades-acukids ]] || die "Failed to write unattended-upgrades policy."

  cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTO_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
AUTO_EOF
  [[ -s /etc/apt/apt.conf.d/20auto-upgrades ]] || die "Failed to write apt periodic policy."

  systemctl enable --now unattended-upgrades >> "$LOG_FILE" 2>&1 || die "Failed to enable unattended-upgrades."
  log "Unattended security upgrades enabled (auto-reboot 3:30 AM if idle)."
}

# ---------------------------------------------------------------------------
# Step 9: Agentic coding harnesses for the admin account (Node.js + CLIs)
# ---------------------------------------------------------------------------
step_agentic_harnesses() {
  log "=== Step 9: Agentic harness setup (Claude Code, Codex, OpenCode) ==="

  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    npm install -g --no-fund --no-audit "@anthropic-ai/claude-code@$CLAUDE_CODE_VERSION" >> "$LOG_FILE" 2>&1 \
      && log "Installed Claude Code CLI $CLAUDE_CODE_VERSION." \
      || { log "WARNING: Claude Code CLI $CLAUDE_CODE_VERSION install failed."; OPTIONAL_FAILURES+=("agent:claude-code"); }

    npm install -g --no-fund --no-audit "@openai/codex@$CODEX_VERSION" >> "$LOG_FILE" 2>&1 \
      && log "Installed Codex CLI $CODEX_VERSION." \
      || { log "WARNING: Codex CLI $CODEX_VERSION install failed."; OPTIONAL_FAILURES+=("agent:codex"); }

    npm install -g --no-fund --no-audit "opencode-ai@$OPENCODE_VERSION" >> "$LOG_FILE" 2>&1 \
      && log "Installed OpenCode CLI $OPENCODE_VERSION." \
      || { log "WARNING: OpenCode CLI $OPENCODE_VERSION install failed."; OPTIONAL_FAILURES+=("agent:opencode"); }
    verify_npm_package_version "@anthropic-ai/claude-code" "$CLAUDE_CODE_VERSION" || OPTIONAL_FAILURES+=("agent:claude-code-version")
    verify_npm_package_version "@openai/codex" "$CODEX_VERSION" || OPTIONAL_FAILURES+=("agent:codex-version")
    verify_npm_package_version "opencode-ai" "$OPENCODE_VERSION" || OPTIONAL_FAILURES+=("agent:opencode-version")
  else
    die "Node.js and npm are required to install the acuKids agentic harnesses."
  fi
}

verify_npm_package_version() {
  local package="$1" expected="$2" installed
  installed=$(npm list -g --depth=0 --json 2>/dev/null | jq -er --arg package "$package" '.dependencies[$package].version') || return 1
  [[ "$installed" == "$expected" ]] || { log "WARNING: installed $package version is $installed, expected $expected."; return 1; }
  log "Verified $package version $installed."
}

# ---------------------------------------------------------------------------
# Step 10: Build the /opt/acukids control repo (config, docs, apply/manage
# scripts) that admin + agentic harnesses use to inspect and modify the
# deployed system going forward.
# ---------------------------------------------------------------------------
step_build_repo() {
  log "=== Step 10: Building /opt/acukids control repo ==="
  install -d -m 0755 "$ACUKIDS_HOME"/{branding,config,scripts,state,homepage} || die "Failed to create the acuKids control repository directories."

  build_children_json
  build_whitelist_sites_conf
  build_blacklist_apps_conf
  sync_managed_app_defaults
  sync_managed_homepage_defaults
  build_whitelist_apps_conf
  build_timekpr_conf
  build_dns_conf
  build_system_meta_json
  record_agent_versions
  if [[ -f "$BRANDING_DIR/acukids-logo.png" && -f "$BRANDING_DIR/acukids-wallpaper.png" ]]; then
    install -m 0644 "$BRANDING_DIR/acukids-logo.png" "$ACUKIDS_HOME/branding/acukids-logo.png" || die "Could not copy the acuKids logo into the control repository."
    install -m 0644 "$BRANDING_DIR/acukids-wallpaper.png" "$ACUKIDS_HOME/branding/acukids-wallpaper.png" || die "Could not copy the acuKids wallpaper into the control repository."
  fi
  if [[ "$RERUN_MODE" == "true" ]]; then
    local metadata_tmp
    metadata_tmp=$(mktemp "$ACUKIDS_HOME/config/system-meta.json.tmp.XXXXXX") || die "Unable to stage upgrade metadata."
    jq --arg version "$SCRIPT_VERSION" --argjson build "$SCRIPT_BUILD" --argjson schema "$CONTROL_SCHEMA_VERSION" --arg upgraded "$(date -Iseconds)" \
      '.acukids_version = $version | .script_build = $build | .config_schema_version = $schema | .last_upgraded = $upgraded' \
      "$ACUKIDS_HOME/config/system-meta.json" > "$metadata_tmp" || die "Unable to update upgrade metadata."
    chmod --reference="$ACUKIDS_HOME/config/system-meta.json" "$metadata_tmp" && mv -f "$metadata_tmp" "$ACUKIDS_HOME/config/system-meta.json" || die "Unable to publish upgrade metadata."
  fi
  build_homepage
  build_agents_md
  if [[ "$RERUN_MODE" == "true" && -f "$ACUKIDS_HOME/scripts/.acukids-generated.sha256" ]]; then
    local saved_mode apply_hash manage_hash
    saved_mode="$RERUN_MODE"
    apply_hash=$(sha256sum "$ACUKIDS_HOME/scripts/acukids-apply.sh" | awk '{print $1}')
    manage_hash=$(sha256sum "$ACUKIDS_HOME/scripts/acukids-manage.sh" | awk '{print $1}')
    local recovery_dir="$ACUKIDS_HOME/state/script-recovery-$(date '+%Y%m%d-%H%M%S-%N')"
    install -d -m 0755 "$recovery_dir" || die "Could not create script recovery copy."
    cp -a "$ACUKIDS_HOME/scripts/acukids-apply.sh" "$ACUKIDS_HOME/scripts/acukids-manage.sh" "$recovery_dir/" || die "Could not save script recovery copy."
    if grep -q "^$apply_hash  acukids-apply.sh$" "$ACUKIDS_HOME/scripts/.acukids-generated.sha256"; then rm -f "$ACUKIDS_HOME/scripts/acukids-apply.sh"; fi
    if grep -q "^$manage_hash  acukids-manage.sh$" "$ACUKIDS_HOME/scripts/.acukids-generated.sha256"; then rm -f "$ACUKIDS_HOME/scripts/acukids-manage.sh"; fi
    RERUN_MODE=false
    build_apply_script
    build_manage_script
    RERUN_MODE="$saved_mode"
  fi
  build_apply_script
  build_manage_script
build_changelog

  # Seed rollback state for a fresh deployment so the first owner change is
  # recoverable even though the initial system writes predate acukids-apply.
  if [[ "$RERUN_MODE" == "false" && ! -d "$ACUKIDS_HOME/state/last-applied/config" ]]; then
    install -d -m 0755 "$ACUKIDS_HOME/state/last-applied" || die "Failed to create initial rollback state."
    cp -a "$ACUKIDS_HOME/config" "$ACUKIDS_HOME/state/last-applied/config" || die "Failed to seed initial rollback configuration."
    [[ ! -f /etc/firefox/policies/policies.json ]] || cp -a /etc/firefox/policies/policies.json "$ACUKIDS_HOME/state/last-applied/policies.json" || die "Failed to seed initial Firefox rollback policy."
  fi

  chmod +x "$ACUKIDS_HOME"/scripts/*.sh || die "Failed to mark acuKids management scripts executable."
  sha256sum "$ACUKIDS_HOME/scripts/acukids-apply.sh" "$ACUKIDS_HOME/scripts/acukids-manage.sh" | sed "s#  $ACUKIDS_HOME/scripts/##" > "$ACUKIDS_HOME/scripts/.acukids-generated.sha256"

  # Ownership: admin group can read/write the whole tree; scripts still need
  # root to actually apply (they re-invoke sudo internally where needed).
  groupadd -f acukids-admin || die "Failed to create the acuKids administrator group."
  usermod -aG acukids-admin "$ADMIN_USERNAME" || die "Failed to add '$ADMIN_USERNAME' to the acuKids administrator group."
  chown -R "root:acukids-admin" "$ACUKIDS_HOME" || die "Failed to set control repository ownership."
  chmod -R g+rwX "$ACUKIDS_HOME" || die "Failed to set control repository permissions."
  find "$ACUKIDS_HOME" -type d -exec chmod g+s {} \; || die "Failed to set control repository directory permissions."

  # Let the admin (and root) run the apply/manage scripts without a password,
  # since they only ever touch the acuKids-managed config surface.
  cat > /etc/sudoers.d/acukids-admin << SUDOERS_EOF
%acukids-admin ALL=(root) NOPASSWD: ${ACUKIDS_HOME}/scripts/acukids-apply.sh, ${ACUKIDS_HOME}/scripts/acukids-apply.sh *, ${ACUKIDS_HOME}/scripts/acukids-manage.sh *
SUDOERS_EOF
  chmod 440 /etc/sudoers.d/acukids-admin || die "Failed to set sudoers file permissions."
  visudo -c -f /etc/sudoers.d/acukids-admin >> "$LOG_FILE" 2>&1 || die "Generated acuKids sudoers policy failed validation."

  # --- git init (local-only, per your decision - no remote configured) ---
  if ! command -v git &>/dev/null; then
    install_packages git
  fi
  command -v git >/dev/null 2>&1 || die "git is required to initialize the acuKids control repository."
  if ! ( cd "$ACUKIDS_HOME" && \
    git init -q && \
    git config user.email "acukids@localhost" && \
    git config user.name "acuKids Deploy" && \
    { [[ -e .gitignore ]] || printf '%s\n' 'state/*' > .gitignore; } && \
    { grep -qxF 'state/*' .gitignore || printf '%s\n' 'state/*' >> .gitignore; } && \
    git add -A && \
    if ! git diff --cached --quiet; then
      git commit -q -m "Update acuKids deployment ($(date '+%Y-%m-%d %H:%M:%S'))"
    fi ); then
    die "Failed to initialize or commit the acuKids control repository."
  fi
  git config --system --add safe.directory "$ACUKIDS_HOME" || die "Failed to register the acuKids repository as safe for the owner."
  log "acuKids local git repository initialized or updated successfully."
}

build_children_json() {
  [[ -e "$ACUKIDS_HOME/config/children.json" ]] && return 0
  {
    echo "["
    local first=1
    for cname in "${CHILD_USERNAMES[@]}"; do
      [[ $first -eq 0 ]] && echo ","
      cat << CHILD_EOF
  {
    "username": "$cname",
    "created": "$(date -Iseconds)",
    "weekday_limit_seconds": 3600,
    "weekend_limit_seconds": 7200,
    "allowed_window": "06:00-19:00"
  }
CHILD_EOF
      first=0
    done
    echo "]"
  } > "$ACUKIDS_HOME/config/children.json"
}

build_whitelist_sites_conf() {
  [[ -e "$ACUKIDS_HOME/config/whitelist-sites.conf" ]] && return 0
  {
    echo "# One site per line (bare domain, no protocol)."
    echo "# Edited by admin or agentic harness, then applied with:"
    echo "#   sudo /opt/acukids/scripts/acukids-apply.sh"
    for s in "${WHITELIST_SITES_DEFAULT[@]}"; do echo "$s"; done
  } > "$ACUKIDS_HOME/config/whitelist-sites.conf"
}

build_homepage_link_files() {
  local defaults="$ACUKIDS_HOME/config/installer-default-homepage-links.json"
  local links="$ACUKIDS_HOME/config/homepage-links.json"
  local blacklist="$ACUKIDS_HOME/config/blacklist-homepage-links.conf"
  if [[ ! -e "$defaults" ]]; then printf '%s\n' "$HOMEPAGE_LINKS_DEFAULT_JSON" > "$defaults"; fi
  if [[ ! -e "$blacklist" ]]; then printf '%s\n' '# Homepage link IDs explicitly rejected by the owner.' > "$blacklist"; fi
  if [[ ! -e "$links" ]]; then cp -p "$defaults" "$links"; fi
}

sync_managed_homepage_defaults() {
  build_homepage_link_files
  local defaults="$ACUKIDS_HOME/config/installer-default-homepage-links.json"
  local links="$ACUKIDS_HOME/config/homepage-links.json"
  local blacklist="$ACUKIDS_HOME/config/blacklist-homepage-links.conf"
  local id obj tmp merged
  merged=$(mktemp "$defaults.tmp.XXXXXX") || die "Could not stage homepage defaults."
  jq -s 'add | unique_by(.id)' "$defaults" <(printf '%s\n' "$HOMEPAGE_LINKS_DEFAULT_JSON") > "$merged" || { rm -f "$merged"; die "Could not update homepage defaults."; }
  mv -f "$merged" "$defaults"
  while IFS= read -r obj; do
    id=$(jq -r '.id' <<<"$obj")
    if ! jq -e --arg id "$id" '.[] | select(.id == $id)' "$links" >/dev/null 2>&1 && ! grep -qxF "$id" "$blacklist"; then
      tmp=$(mktemp "$links.tmp.XXXXXX") || die "Could not stage homepage links."
      jq --argjson obj "$obj" '. + [$obj]' "$links" > "$tmp" || { rm -f "$tmp"; die "Could not update homepage links."; }
      mv -f "$tmp" "$links"
    fi
  done < <(jq -c '.[]' "$defaults")
}

build_whitelist_apps_conf() {
  [[ -e "$ACUKIDS_HOME/config/whitelist-apps.conf" ]] && return 0
  {
    echo "# One .desktop filename per line (from /usr/share/applications or"
    echo "# /var/lib/snapd/desktop/applications). Apps NOT listed here are"
    echo "# hidden from child accounts' app grids. This list was generated by"
    echo "# inspecting what each installed package actually shipped (via"
    echo "# dpkg -L), not guessed - if you install a new app and want it"
    echo "# visible to kids, find its real filename with:"
    echo "#   dpkg -L <package-name> | grep .desktop"
    echo "# then add it here and apply changes with:"
    echo "#   sudo /opt/acukids/scripts/acukids-apply.sh"
    for a in "${WHITELIST_APPS_RUNTIME[@]:-${WHITELIST_APPS_DEFAULT[@]}}"; do echo "$a"; done
  } > "$ACUKIDS_HOME/config/whitelist-apps.conf"
}

build_blacklist_apps_conf() {
  [[ -e "$ACUKIDS_HOME/config/blacklist-apps.conf" ]] && return 0
  cat > "$ACUKIDS_HOME/config/blacklist-apps.conf" << 'BLACKLIST_APPS_EOF'
# One .desktop filename per line that the owner never wants automatically
# reintroduced by a future acuKids upgrade.
BLACKLIST_APPS_EOF
}

# Track installer-provided apps separately from the owner's effective list.
# On upgrade, only newly introduced defaults are added, and explicit owner
# blacklists always win.
sync_managed_app_defaults() {
  local managed="$ACUKIDS_HOME/config/installer-default-apps.conf"
  local blacklist="$ACUKIDS_HOME/config/blacklist-apps.conf"
  build_blacklist_apps_conf
  if [[ ! -e "$managed" ]]; then
    {
      echo '# Apps supplied by the acuKids installer; do not edit manually.'
      printf '%s\n' "${WHITELIST_APPS_RUNTIME[@]:-${WHITELIST_APPS_DEFAULT[@]}}"
    } > "$managed"
    return 0
  fi
  local app
  for app in "${WHITELIST_APPS_RUNTIME[@]:-${WHITELIST_APPS_DEFAULT[@]}}"; do
    if ! grep -qxF "$app" "$managed"; then
      printf '%s\n' "$app" >> "$managed"
      if ! grep -qxF "$app" "$blacklist" && ! grep -qxF "$app" "$ACUKIDS_HOME/config/whitelist-apps.conf"; then
        printf '%s\n' "$app" >> "$ACUKIDS_HOME/config/whitelist-apps.conf"
      fi
    fi
  done
}

build_timekpr_conf() {
  [[ -e "$ACUKIDS_HOME/config/timekpr-defaults.conf" ]] && return 0
  cat > "$ACUKIDS_HOME/config/timekpr-defaults.conf" << TIMEKPR_EOF
# Default schedule applied to every child account at deploy time.
# Per-child overrides can be made directly with timekpra, or by editing
# config/children.json and re-running acukids-apply.sh.
WEEKDAY_LIMIT_SECONDS=3600
WEEKEND_LIMIT_SECONDS=7200
ALLOWED_WINDOW_START=06:00
ALLOWED_WINDOW_END=19:00
TIMEKPR_EOF
}

build_dns_conf() {
  [[ -e "$ACUKIDS_HOME/config/dns.conf" ]] && return 0
  cat > "$ACUKIDS_HOME/config/dns.conf" << DNS_CONF_EOF
# Cloudflare for Families - No Malware or Adult Content
DNS_V4_PRIMARY=1.1.1.3
DNS_V4_SECONDARY=1.0.0.3
DNS_V6_PRIMARY=2606:4700:4700::1113
DNS_V6_SECONDARY=2606:4700:4700::1003
DNS_CONF_EOF
}

build_system_meta_json() {
  [[ -e "$ACUKIDS_HOME/config/system-meta.json" ]] && return 0
  cat > "$ACUKIDS_HOME/config/system-meta.json" << META_EOF
{
  "acukids_version": "$SCRIPT_VERSION",
  "script_build": $SCRIPT_BUILD,
  "config_schema_version": $CONTROL_SCHEMA_VERSION,
  "hostname": "$ACUKIDS_HOSTNAME",
  "deployed": "$(date -Iseconds)",
  "original_installer_account": $(if [[ -n "${ORIGINAL_ADMIN_USER:-}" ]]; then printf '"%s"' "$ORIGINAL_ADMIN_USER"; else printf 'null'; fi),
  "original_installer_account_hidden": ${HIDE_ORIGINAL_ACCOUNT:-false},
  "admin_account": "$ADMIN_USERNAME",
  "child_group": "$CHILD_GROUP",
  "dconf_profile": "$DCONF_PROFILE_NAME",
  "browser_kids": "firefox (deb, Mozilla repo, policies.json whitelist)",
  "browser_admin": "chromium (snap, unrestricted)",
  "timekpr_next_version": "$TIMEKPR_INSTALLED_VERSION",
  "timekpr_next_source": "$TIMEKPR_PPA",
  "agent_versions_requested": {
    "@anthropic-ai/claude-code": "$CLAUDE_CODE_VERSION",
    "@openai/codex": "$CODEX_VERSION",
    "opencode-ai": "$OPENCODE_VERSION"
  },
  "node_version": "$(node --version 2>/dev/null || echo unavailable)"
}
META_EOF
}

record_agent_versions() {
  command -v npm >/dev/null 2>&1 || die "npm is required to record agent versions."
  command -v node >/dev/null 2>&1 || die "Node.js is required to record agent versions."
  local installed agent_versions tmp
  installed=$(npm list -g --depth=0 --json 2>/dev/null) || die "Unable to inspect globally installed agent packages."
  agent_versions=$(printf '%s' "$installed" | jq -c '{"@anthropic-ai/claude-code": (.dependencies["@anthropic-ai/claude-code"].version // "unavailable"), "@openai/codex": (.dependencies["@openai/codex"].version // "unavailable"), "opencode-ai": (.dependencies["opencode-ai"].version // "unavailable") }') || die "Unable to encode installed agent versions."
  tmp=$(mktemp "$ACUKIDS_HOME/config/system-meta.json.tmp.XXXXXX") || die "Unable to stage agent version metadata."
  if ! jq --arg node "$(node --version)" --argjson agents "$agent_versions" '.node_version = $node | .agent_versions = $agents' "$ACUKIDS_HOME/config/system-meta.json" > "$tmp"; then
    rm -f "$tmp"
    die "Unable to update agent version metadata."
  fi
  mv -f "$tmp" "$ACUKIDS_HOME/config/system-meta.json" || die "Unable to publish agent version metadata."
  log "Recorded Node.js and agent CLI versions in deployment metadata."
}

build_homepage() {
  build_homepage_link_files
  local index="$ACUKIDS_HOME/homepage/index.html"
  local marker="$ACUKIDS_HOME/homepage/.acukids-generated.sha256"
  local legacy_hash="1954e0047984d03344f67245b6a66b3157f001305e28904d3fbee6a32265774c"
  local current_hash="" replace=false staged
  if [[ ! -e "$index" ]]; then
    replace=true
  else
    current_hash=$(sha256sum "$index" | awk '{print $1}') || die "Could not inspect the existing homepage."
    if [[ "$current_hash" == "$legacy_hash" ]] || grep -qxF "$current_hash  index.html" "$marker" 2>/dev/null; then
      replace=true
    fi
  fi
  [[ "$replace" == "true" ]] || return 0
  if [[ -f "$BRANDING_DIR/acukids-logo.png" ]]; then
    install -m 0644 "$BRANDING_DIR/acukids-logo.png" "$ACUKIDS_HOME/homepage/acukids-logo.png" || die "Could not install homepage logo."
  fi

  staged=$(mktemp "$ACUKIDS_HOME/homepage/.index.html.XXXXXX") || die "Could not stage the acuKids homepage."
  cat > "$staged" << 'HOMEPAGE_EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>acuKids</title>
<style>
  body { font-family: sans-serif; background:#fef9e7; text-align:center; padding:40px; }
  .brand { width:min(280px, 60vw); height:auto; }
  h1 { color:#2e86c1; font-size:2.4em; margin:16px 0 0; }
  .grid { display:flex; flex-wrap:wrap; justify-content:center; gap:24px; margin-top:40px; }
  a.tile {
    display:block; width:220px; padding:24px; border-radius:20px;
    background:#ffffff; box-shadow:0 4px 10px rgba(0,0,0,0.15);
    text-decoration:none; color:#333; font-size:1.4em; font-weight:bold;
  }
  a.tile:hover { background:#d6eaf8; }
</style>
</head>
<body>
  <img class="brand" src="acukids-logo.png" alt="acuKids" onerror="this.hidden=true">
  <h1>Welcome! What would you like to explore?</h1>
  <div class="grid">
HOMEPAGE_EOF
  while IFS= read -r link; do
    label=$(jq -r '.label' <<<"$link" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
    url=$(jq -r '.url' <<<"$link" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
    printf '    <a class="tile" href="%s">%s</a>\n' "$url" "$label" >> "$staged"
  done < <(jq -c '.[]' "$ACUKIDS_HOME/config/homepage-links.json")
  cat >> "$staged" <<'HOMEPAGE_CLOSE_EOF'
  </div>
</body>
</html>
HOMEPAGE_CLOSE_EOF
  chmod 0644 "$staged" && mv -f "$staged" "$index" || { rm -f "$staged"; die "Could not install the acuKids homepage."; }
  printf '%s  index.html\n' "$(sha256sum "$index" | awk '{print $1}')" > "$marker" || die "Could not record the generated homepage hash."
  chmod 0644 "$marker" || die "Could not protect the generated homepage hash."
}

build_agents_md() {
  cat > "$ACUKIDS_HOME/AGENTS.md" << AGENTS_EOF
# acuKids System Manifest (for agentic coding harnesses)

This file is read by agentic harnesses (Claude Code, Codex, OpenCode, etc.)
run by the admin from their acuKids admin account. It describes what has
been configured, where the canonical config lives, and how to safely
change it. This same file is also symlinked as \`CLAUDE.md\` for harnesses
that specifically look for that name.

## Golden rule

**Never edit live system files directly** (e.g. \`/etc/firefox/policies/policies.json\`,
\`/etc/dconf/db/...\`, timekpr settings). Always:

1. Edit the canonical source under \`/opt/acukids/config/\`.
2. Run \`sudo /opt/acukids/scripts/acukids-apply.sh\` to regenerate and apply
   the live configuration from those sources.
3. Confirm the change in \`/opt/acukids/CHANGELOG.md\` (the apply script
   appends automatically) and commit the change with git:
   \`git -C /opt/acukids add -A && git -C /opt/acukids commit -m "..."\`.

The apply script snapshots the previous live state into \`/opt/acukids/state/\`
before applying, so a bad change can be rolled back with:
\`sudo /opt/acukids/scripts/acukids-apply.sh --rollback\`.

## System overview

- Hostname: \`$ACUKIDS_HOSTNAME\`
- Original Ubuntu installer account: \`${ORIGINAL_ADMIN_USER:-none}\` (kept as
  fallback login only, auto-login disabled, not used day-to-day).
- Admin account: \`$ADMIN_USERNAME\` (sudo, member of \`acukids-admin\` group
  which owns this directory and can run the apply/manage scripts
  passwordlessly via sudoers).
- Child accounts: see \`config/children.json\`. All members of the
  \`$CHILD_GROUP\` Linux group.
- Child login: 4-digit numeric PIN (implemented as a short Linux password -
  Ubuntu has no native "PIN pad", GDM just shows a normal password field).

## Directory layout

\`\`\`
/opt/acukids/
  AGENTS.md              <- this file (symlinked as CLAUDE.md)
  CHANGELOG.md            append-only log of every deployment/apply action
  branding/               verified acuKids logo and child wallpaper assets
  homepage/index.html     Firefox homepage shown to child accounts
  config/
    children.json         child accounts + per-child time-limit overrides
    whitelist-sites.conf  domains children's Firefox may visit
    homepage-links.json   owner-selected links shown on the child homepage
    installer-default-homepage-links.json installer-supplied homepage defaults
    blacklist-homepage-links.conf homepage IDs the owner never wants reintroduced
    whitelist-apps.conf   .desktop files visible in children's app grid
    blacklist-apps.conf   .desktop files the owner never wants reintroduced
    installer-default-apps.conf apps previously supplied by the installer
    timekpr-defaults.conf default weekday/weekend time budget + window
    dns.conf              DNS filtering resolvers in use
    system-meta.json      versioning / high-level facts about this deployment
  scripts/
    acukids-apply.sh       regenerates live config from config/*, restarts
                            services, snapshots previous state, logs to
                            CHANGELOG.md. Supports --rollback.
    acukids-manage.sh      interactive/CLI helper: add/remove child, reset
                            today's time, change PIN, add site/app to
                            whitelist and homepage links. Calls acukids-apply.sh automatically.
  state/                  timestamped snapshots of previously-applied config,
                            used by --rollback
\`\`\`

## How each subsystem is implemented (so you know what "applying" touches)

| Concern            | Canonical source                        | Live system location(s) |
|---------------------|------------------------------------------|--------------------------|
| DNS filtering       | \`config/dns.conf\`                       | \`/etc/systemd/resolved.conf.d/acukids-dns.conf\`, NetworkManager per-connection DNS |
| Browser whitelist   | \`config/whitelist-sites.conf\`           | \`/etc/firefox/policies/policies.json\` (\`WebsiteFilter\`) |
| Homepage links      | \`config/homepage-links.json\` + blacklist | \`homepage/index.html\` (generated when unchanged) |
| App menu lockdown   | \`config/whitelist-apps.conf\` + \`blacklist-apps.conf\` | \`~/.local/share/applications/*.desktop\` (NoDisplay overrides) in each child home |
| Time limits         | \`config/children.json\` + \`config/timekpr-defaults.conf\` | \`timekpra\` daemon state (via CLI, not flat files) |
| Desktop lockdown    | (fixed by deploy script)                  | \`/etc/dconf/db/${DCONF_PROFILE_NAME}.d/\`, profile \`${DCONF_PROFILE_NAME}\` |
| Branding            | \`branding/\`                             | \`/usr/share/acukids/branding/\`, child dconf wallpaper, GDM logo |
| Accounts            | \`config/children.json\`                  | \`/etc/passwd\`, \`/etc/shadow\`, group \`$CHILD_GROUP\` |
| Updates             | (fixed by deploy script)                  | \`/etc/apt/apt.conf.d/50unattended-upgrades-acukids\` |

The child application directory \`~/.local/share/applications/\` is
authoritative acuKids-managed state. Reconciliation may remove every existing
user-level \`.desktop\` entry there and rebuild the exact allowlisted view;
children and parents must not treat that directory as an independent source
of configuration.

## Browser split (important context for any browser-related change)

Firefox enterprise policies (\`policies.json\`) apply **machine-wide**, not
per-user. To give children a locked-down browser while still letting the
admin browse freely, this deployment intentionally uses **two different
browsers**:

- **Firefox (.deb, Mozilla's own APT repo)** - locked down via
  \`policies.json\`, strict site whitelist, used by children.
- **Chromium (snap, default Ubuntu build)** - left unrestricted, intended
  for the admin account only.

If you need to change what children can browse to, edit
\`config/whitelist-sites.conf\` and re-run the apply script - do not edit
\`policies.json\` directly, it will be overwritten on the next apply.

\`WebsiteFilter\`'s \`Block: ["<all_urls>"]\` matches every URL scheme, not
just http/https - this includes \`file://\`. The generated exceptions list
always includes \`file:///opt/acukids/homepage/*\` for this reason (the
local homepage would otherwise be blocked by its own filter). If you ever
add another local \`file://\` resource that children need to open, it needs
its own exception in this same list, or it will be silently blocked the
same way.

Firefox on Ubuntu 26.04 defaults to a **snap package**, which does not
reliably honor \`policies.json\`. This deployment removes the snap and pins
apt (see \`/etc/apt/preferences.d/mozilla-firefox\`) so a system upgrade
cannot silently reintroduce it. If Firefox ever reverts to opening as a
snap, check that pin file first.

## Finding the real filename when adding a new app to the whitelist

Modern packages often ship \`.desktop\` files with reverse-DNS-style names
that don't match the package name (e.g. Krita's is \`org.kde.krita.desktop\`,
GCompris's is \`org.kde.gcompris.desktop\`, Stellarium's is
\`org.stellarium.Stellarium.desktop\`). Never guess this filename - find the
real one after installing the package:

\`\`\`bash
sudo apt install <package-name>
dpkg -L <package-name> | grep '\\.desktop$'
\`\`\`

Add the exact basename that command prints to
\`config/whitelist-apps.conf\`, then run \`acukids-apply.sh\`. Guessing wrong
here is what silently hides an installed, working app from children - it
has happened before in this deployment's history (see CHANGELOG.md).

## The original installer / fallback account

Whether this account is hidden from the GDM login picker is recorded in
\`config/system-meta.json\` (\`original_installer_account_hidden\`). Either
way it is never deleted and never loses its password - it exists purely
as a recovery path if the admin account is ever locked out. To change its
visibility:

\`\`\`bash
sudo /opt/acukids/scripts/acukids-manage.sh hide-fallback-account <username>
sudo /opt/acukids/scripts/acukids-manage.sh show-fallback-account <username>
\`\`\`

Hiding it only removes it from the clickable user list at login - the
account still works if its username is typed manually, so this is safe
to do without human confirmation. Deleting it outright is not (see below).

## Safe things an agent can do autonomously

- Add/remove a child account (via \`acukids-manage.sh\`)
- Add/remove a whitelisted site or app (look up the real \`.desktop\`
  filename first, per the section above)
- Adjust an individual child's time limit or allowed window
- Change a child's PIN
- Hide/show the original installer account in the login picker
- Review \`/var/log/acukids-deploy.log\` and \`CHANGELOG.md\` to explain what
  has changed and when

## Changes that require explicit admin (human) confirmation first

- Disabling DNS filtering, the browser whitelist, or desktop lockdown
  entirely
- Deleting the original installer account
- Changing which browser is used for children
- Anything that would grant a child account sudo/admin rights
- Modifying \`/etc/sudoers.d/acukids-admin\`

## Useful commands

\`\`\`bash
# Apply any pending config/ changes to the live system
sudo /opt/acukids/scripts/acukids-apply.sh

# Roll back to the previous applied state
sudo /opt/acukids/scripts/acukids-apply.sh --rollback

# Add a child interactively
sudo /opt/acukids/scripts/acukids-manage.sh add-child

# Reset a child's time budget for today
sudo /opt/acukids/scripts/acukids-manage.sh reset-time <username>

# Check a child's current timekpr status
timekpra --userinfo <username>
\`\`\`
AGENTS_EOF

  ln -sf AGENTS.md "$ACUKIDS_HOME/CLAUDE.md"
}

build_apply_script() {
  cat > "$ACUKIDS_HOME/scripts/acukids-apply.sh" << 'APPLY_SCRIPT_EOF'
#!/usr/bin/env bash
#
# acukids-apply.sh
#
# Regenerates live system configuration from the canonical files under
# /opt/acukids/config/, restarts affected services, snapshots the previous
# last successfully applied state, and logs the action to CHANGELOG.md.
#
# Usage:
#   sudo /opt/acukids/scripts/acukids-apply.sh              # apply config/
#   sudo /opt/acukids/scripts/acukids-apply.sh --rollback   # restore last snapshot
#
set -uo pipefail

ACUKIDS_HOME="${ACUKIDS_HOME:-/opt/acukids}"
CONFIG_DIR="$ACUKIDS_HOME/config"
STATE_DIR="$ACUKIDS_HOME/state"
CHANGELOG="$ACUKIDS_HOME/CHANGELOG.md"
CHILD_GROUP="acukids-children"
DCONF_PROFILE_NAME="acukids-child"
TS="$(date '+%Y%m%d-%H%M%S')"
LAST_APPLIED_DIR="$STATE_DIR/last-applied"
APPLY_FAILURES=()

require_root() {
  [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 $*" >&2; exit 1; }
  acquire_lock
}

LOCK_FILE="/run/lock/acukids.lock"
acquire_lock() {
  [[ "${ACUKIDS_LOCK_HELD:-false}" == "true" ]] && return 0
  install -d -m 0755 "$(dirname "$LOCK_FILE")" || { echo "Unable to create lock parent." >&2; exit 1; }
  exec 9>"$LOCK_FILE" || { echo "Unable to open acuKids lock." >&2; exit 1; }
  flock -n 9 || { echo "Another acuKids operation is already running; retry after it completes." >&2; exit 1; }
  export ACUKIDS_LOCK_HELD=true
}

changelog() {
  echo "- $(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$CHANGELOG"
}

run_apply_step() {
  local name="$1"
  shift
  if ! "$@"; then
    APPLY_FAILURES+=("$name")
  fi
}

validate_config() {
  local ok=0 site app line
  for required in "$CONFIG_DIR/children.json" "$CONFIG_DIR/whitelist-sites.conf" "$CONFIG_DIR/whitelist-apps.conf" "$CONFIG_DIR/homepage-links.json" "$CONFIG_DIR/blacklist-homepage-links.conf" "$CONFIG_DIR/timekpr-defaults.conf" "$CONFIG_DIR/dns.conf" "$CONFIG_DIR/system-meta.json"; do
    if [[ ! -f "$required" ]]; then
      printf 'Configuration error: missing %s\n' "$required" >&2
      ok=1
    fi
  done
  for required_cmd in jq id getent install cp mv nmcli resolvectl; do
    if ! command -v "$required_cmd" >/dev/null 2>&1; then
      printf 'Configuration error: required command is unavailable: %s\n' "$required_cmd" >&2
      ok=1
    fi
  done

  if [[ -f "$CONFIG_DIR/children.json" ]]; then
    if ! jq -e 'type == "array" and length > 0 and ([.[].username] | unique | length) == length and all(.[]; (.username | type == "string" and test("^[a-z][-a-z0-9_]{2,31}$")) and (.weekday_limit_seconds | numbers and . >= 0 and . <= 86400) and (.weekend_limit_seconds | numbers and . >= 0 and . <= 86400) and (.allowed_window | type == "string" and test("^(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]-(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$")))' "$CONFIG_DIR/children.json" >/dev/null 2>&1; then
      printf 'Configuration error: children.json must contain unique valid usernames, nonnegative numeric limits, and HH:MM-HH:MM windows.\n' >&2
      ok=1
    fi
    if getent group "$CHILD_GROUP" >/dev/null 2>&1; then
      while IFS= read -r username; do
        if id "$username" >/dev/null 2>&1 && ! getent group "$CHILD_GROUP" | grep -qw -- "$username"; then
          printf 'Configuration error: existing account is not an acuKids child: %s\n' "$username" >&2
          ok=1
        fi
      done < <(jq -r '.[].username' "$CONFIG_DIR/children.json" 2>/dev/null)
    fi
  fi

  if [[ -f "$CONFIG_DIR/homepage-links.json" ]]; then
    if ! jq -e 'type == "array" and all(.[]; (.id|type == "string" and test("^[a-z0-9][a-z0-9-]{1,63}$")) and (.label|type == "string" and length > 0 and length <= 120) and (.url|type == "string" and test("^https://[^[:space:]]+$"))) and ([.[].id] | unique | length) == length' "$CONFIG_DIR/homepage-links.json" >/dev/null 2>&1; then
      printf 'Configuration error: homepage-links.json contains invalid or duplicate entries.\n' >&2
      ok=1
    fi
    while IFS= read -r homepage_url; do
      local homepage_host covered=false site_host
      homepage_host=$(sed -E 's#^https://([^/:?#]+).*#\1#' <<<"$homepage_url")
      while IFS= read -r site_host || [[ -n "$site_host" ]]; do
        [[ -z "$site_host" || "$site_host" == \#* ]] && continue
        site_host="${site_host%%/*}"
        if [[ "$homepage_host" == "$site_host" || "$homepage_host" == *".$site_host" ]]; then covered=true; break; fi
      done < "$CONFIG_DIR/whitelist-sites.conf"
      if [[ "$covered" != true ]]; then
        printf 'Configuration error: homepage URL is not covered by whitelist-sites.conf: %s\n' "$homepage_url" >&2
        ok=1
      fi
    done < <(jq -r '.[].url' "$CONFIG_DIR/homepage-links.json" 2>/dev/null)
  fi

  if [[ -f "$CONFIG_DIR/system-meta.json" ]] && ! jq -e '.admin_account | type == "string" and test("^[a-z][-a-z0-9_]{2,31}$")' "$CONFIG_DIR/system-meta.json" >/dev/null 2>&1; then
    printf 'Configuration error: system-meta.json has an invalid admin_account.\n' >&2
    ok=1
  fi

  if [[ -f "$CONFIG_DIR/whitelist-sites.conf" ]]; then
    while IFS= read -r site || [[ -n "$site" ]]; do
      [[ -z "$site" || "$site" == \#* ]] && continue
      if [[ ! "$site" =~ ^[A-Za-z0-9.-]+(/[A-Za-z0-9._~:/?#@!\$%\&\(\)\*+,;=-]+)?$ ]]; then
        printf 'Configuration error: invalid website allowlist entry: %s\n' "$site" >&2
        ok=1
      fi
    done < "$CONFIG_DIR/whitelist-sites.conf"
  fi

  if [[ -f "$CONFIG_DIR/whitelist-apps.conf" ]]; then
    while IFS= read -r app || [[ -n "$app" ]]; do
      [[ -z "$app" || "$app" == \#* ]] && continue
      if [[ ! "$app" =~ ^[A-Za-z0-9._-]+\.desktop$ ]]; then
        printf 'Configuration error: invalid desktop-file allowlist entry: %s\n' "$app" >&2
        ok=1
      fi
    done < "$CONFIG_DIR/whitelist-apps.conf"
  fi

  if [[ -f "$CONFIG_DIR/dns.conf" ]]; then
    for key in DNS_V4_PRIMARY DNS_V4_SECONDARY DNS_V6_PRIMARY DNS_V6_SECONDARY; do
      if ! grep -Eq "^${key}=[A-Fa-f0-9:.]+$" "$CONFIG_DIR/dns.conf"; then
        printf 'Configuration error: missing or invalid DNS value for %s in dns.conf.\n' "$key" >&2
        ok=1
      fi
    done
  fi

  if [[ -f "$CONFIG_DIR/timekpr-defaults.conf" ]]; then
    for key in WEEKDAY_LIMIT_SECONDS WEEKEND_LIMIT_SECONDS; do
      if ! grep -Eq "^${key}=[0-9]+$" "$CONFIG_DIR/timekpr-defaults.conf"; then
        printf 'Configuration error: missing or invalid %s in timekpr-defaults.conf.\n' "$key" >&2
        ok=1
      fi
    done
    for key in ALLOWED_WINDOW_START ALLOWED_WINDOW_END; do
      if ! grep -Eq "^${key}=(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$" "$CONFIG_DIR/timekpr-defaults.conf"; then
        printf 'Configuration error: missing or invalid %s in timekpr-defaults.conf.\n' "$key" >&2
        ok=1
      fi
    done
  fi
  return "$ok"
}

snapshot_previous_state() {
  [[ -d "$LAST_APPLIED_DIR/config" ]] || return 0
  TS="$(date '+%Y%m%d-%H%M%S-%N')-$$-${RANDOM}"
  install -d "$STATE_DIR/$TS" || return 1
  cp -a "$LAST_APPLIED_DIR/config" "$STATE_DIR/$TS/config" || return 1
  if [[ -f "$LAST_APPLIED_DIR/policies.json" ]]; then
    cp "$LAST_APPLIED_DIR/policies.json" "$STATE_DIR/$TS/policies.json" || return 1
  fi
  local parent=""
  [[ -f "$STATE_DIR/LATEST" ]] && parent=$(cat "$STATE_DIR/LATEST")
  printf '%s\n' "$parent" > "$STATE_DIR/$TS/PARENT"
  printf '%s\n' "$TS" > "$STATE_DIR/LATEST"
}

record_last_applied_state() {
  local staged old
  staged=$(mktemp -d "$STATE_DIR/.last-applied.XXXXXX") || return 1
  cp -a "$CONFIG_DIR" "$staged/config" || { rm -rf "$staged"; return 1; }
  if [[ -f /etc/firefox/policies/policies.json ]]; then
    cp /etc/firefox/policies/policies.json "$staged/policies.json" || { rm -rf "$staged"; return 1; }
  fi
  old=$(mktemp -d "$STATE_DIR/.last-applied-old.XXXXXX") || { rm -rf "$staged"; return 1; }
  rmdir "$old" || { rm -rf "$staged"; return 1; }
  if [[ -e "$LAST_APPLIED_DIR" ]]; then
    mv "$LAST_APPLIED_DIR" "$old" || { rm -rf "$staged" "$old"; return 1; }
  fi
  if ! mv "$staged" "$LAST_APPLIED_DIR"; then
    [[ -e "$old" ]] && mv "$old" "$LAST_APPLIED_DIR"
    rm -rf "$staged" "$old"
    return 1
  fi
  rm -rf "$old"
}

rollback() {
  require_root
  local latest
  latest=$(cat "$STATE_DIR/LATEST" 2>/dev/null || true)
  [[ -n "$latest" && -d "$STATE_DIR/$latest/config" ]] || { echo "No snapshot to roll back to." >&2; exit 1; }
  echo "Rolling back to snapshot $latest ..."
  local config_backup
  config_backup=$(mktemp -d "$STATE_DIR/.rollback-config.XXXXXX") || { echo "Could not stage rollback backup." >&2; exit 1; }
  cp -a "$CONFIG_DIR/." "$config_backup/" || { rm -rf "$config_backup"; echo "Could not back up current configuration." >&2; exit 1; }
  if ! cp -a "$STATE_DIR/$latest/config/." "$CONFIG_DIR/"; then
    rm -rf "$config_backup"
    echo "Could not restore snapshot configuration; current configuration was retained." >&2
    exit 1
  fi
  local target_children current_child target_child
  target_children=""
  if [[ -f "$CONFIG_DIR/children.json" ]] && jq -e 'type == "array"' "$CONFIG_DIR/children.json" >/dev/null 2>&1; then
    target_children=$(jq -r '.[].username' "$CONFIG_DIR/children.json") || { echo "Snapshot has invalid child configuration." >&2; exit 1; }
  fi
  if [[ -f "$config_backup/children.json" && -n "$target_children" ]]; then
    while IFS= read -r current_child; do
      [[ -z "$current_child" ]] && continue
      if ! grep -qxF "$current_child" <<< "$target_children"; then
        deluser "$current_child" >/dev/null 2>&1 || { echo "Could not remove child account $current_child during rollback." >&2; exit 1; }
      fi
    done < <(jq -r '.[].username' "$config_backup/children.json")
  fi
  while IFS= read -r target_child; do
    [[ -z "$target_child" ]] && continue
    if ! id "$target_child" >/dev/null 2>&1; then
      adduser --disabled-password --gecos "$target_child" "$target_child" >/dev/null 2>&1 || { echo "Could not restore child account $target_child; set its PIN after manual recovery." >&2; exit 1; }
      usermod -aG "$CHILD_GROUP" "$target_child" || { echo "Could not restore child group membership for $target_child." >&2; exit 1; }
      echo "Restored child account $target_child without a PIN; owner must run set-pin before login."
    fi
  done <<< "$target_children"
  local parent=""
  [[ -f "$STATE_DIR/$latest/PARENT" ]] && parent=$(cat "$STATE_DIR/$latest/PARENT")
  if ! apply_all --restored-state; then
    rm -rf "$CONFIG_DIR" && mv "$config_backup" "$CONFIG_DIR"
    chmod 2775 "$CONFIG_DIR" 2>/dev/null || true
    getent group acukids-admin >/dev/null 2>&1 && chown root:acukids-admin "$CONFIG_DIR" 2>/dev/null || true
    echo "Rollback failed; previous configuration was restored. Snapshot $latest remains available." >&2
    exit 1
  fi
  rm -rf "$config_backup"
  if [[ -n "$parent" && -d "$STATE_DIR/$parent/config" ]]; then
    printf '%s\n' "$parent" > "$STATE_DIR/LATEST"
  else
    rm -f "$STATE_DIR/LATEST"
  fi
  changelog "ROLLBACK to snapshot $latest"
}

apply_dns() {
  local conf="$CONFIG_DIR/dns.conf"
  [[ -f "$conf" ]] || return 0
  local DNS_V4_PRIMARY DNS_V4_SECONDARY DNS_V6_PRIMARY DNS_V6_SECONDARY
  DNS_V4_PRIMARY=$(sed -n 's/^DNS_V4_PRIMARY=//p' "$conf")
  DNS_V4_SECONDARY=$(sed -n 's/^DNS_V4_SECONDARY=//p' "$conf")
  DNS_V6_PRIMARY=$(sed -n 's/^DNS_V6_PRIMARY=//p' "$conf")
  DNS_V6_SECONDARY=$(sed -n 's/^DNS_V6_SECONDARY=//p' "$conf")
  [[ -n "$DNS_V4_PRIMARY" && -n "$DNS_V4_SECONDARY" && -n "$DNS_V6_PRIMARY" && -n "$DNS_V6_SECONDARY" ]] || return 1
  install -d /etc/systemd/resolved.conf.d || return 1
  local staged
  staged=$(mktemp /etc/systemd/resolved.conf.d/.acukids-dns.XXXXXX) || return 1
  cat > "$staged" << DNS_EOF
[Resolve]
DNS=${DNS_V4_PRIMARY:-1.1.1.3} ${DNS_V4_SECONDARY:-1.0.0.3} ${DNS_V6_PRIMARY:-} ${DNS_V6_SECONDARY:-}
FallbackDNS=${DNS_V4_PRIMARY:-1.1.1.3} ${DNS_V4_SECONDARY:-1.0.0.3}
DNSOverTLS=opportunistic
DNS_EOF
  chmod 0644 "$staged" && mv -f "$staged" /etc/systemd/resolved.conf.d/acukids-dns.conf || { rm -f "$staged"; return 1; }
  systemctl restart systemd-resolved 2>/dev/null || return 1
  resolvectl dns >/dev/null 2>&1 || return 1

  command -v nmcli >/dev/null 2>&1 || return 1
  local uuid connection_uuids
  connection_uuids=$(nmcli -t -f UUID connection show) || return 1
  while IFS= read -r uuid || [[ -n "$uuid" ]]; do
    [[ -z "$uuid" ]] && continue
    nmcli connection modify uuid "$uuid" ipv4.dns "$DNS_V4_PRIMARY $DNS_V4_SECONDARY" ipv4.ignore-auto-dns yes || return 1
    nmcli connection modify uuid "$uuid" ipv6.dns "$DNS_V6_PRIMARY $DNS_V6_SECONDARY" ipv6.ignore-auto-dns yes || return 1
  done <<< "$connection_uuids"
  install -d /etc/NetworkManager/dispatcher.d || return 1
  local dispatcher
  dispatcher=$(mktemp /etc/NetworkManager/dispatcher.d/.acukids-dns.XXXXXX) || return 1
  cat > "$dispatcher" << DISPATCHER_EOF
#!/bin/sh
[ "\${2:-}" = up ] || exit 0
[ -n "\${CONNECTION_UUID:-}" ] || exit 0
nmcli connection modify uuid "\$CONNECTION_UUID" \\
  ipv4.dns "$DNS_V4_PRIMARY $DNS_V4_SECONDARY" ipv4.ignore-auto-dns yes \\
  ipv6.dns "$DNS_V6_PRIMARY $DNS_V6_SECONDARY" ipv6.ignore-auto-dns yes
DISPATCHER_EOF
  chmod 0755 "$dispatcher" && mv -f "$dispatcher" /etc/NetworkManager/dispatcher.d/99-acukids-dns || { rm -f "$dispatcher"; return 1; }
}

apply_firefox_whitelist() {
  local sites_file="$CONFIG_DIR/whitelist-sites.conf"
  [[ -f "$sites_file" ]] || return 0
  # Always include the local homepage file - the WebsiteFilter "Block":
  # ["<all_urls>"] pattern matches every URL scheme, including file://, so
  # without this exception Firefox blocks its own homepage on startup.
  local sites_json="[\"file:///opt/acukids/homepage/*\""
  while IFS= read -r site; do
    [[ -z "$site" || "$site" == \#* ]] && continue
    sites_json+=",\"*://*.${site}/*\",\"*://${site}/*\""
  done < "$sites_file"
  sites_json+="]"

  install -d /etc/firefox/policies || return 1
  local staged
  staged=$(mktemp /etc/firefox/policies/.acukids-policy.XXXXXX) || return 1
  cat > "$staged" << POLICY_EOF
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableDeveloperTools": true,
    "DisableFirefoxAccounts": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableSetDesktopBackground": true,
    "DisableSecurityBypass": { "InvalidCertificate": true, "SafeBrowsing": true },
    "DisablePrivateBrowsing": true,
    "DisableFormHistory": false,
    "DontCheckDefaultBrowser": true,
    "NoDefaultBookmarks": true,
    "OfferToSaveLogins": false,
    "PasswordManagerEnabled": false,
    "PopupBlocking": { "Default": true, "Locked": true },
    "HardwareAcceleration": true,
    "Homepage": { "URL": "file:///opt/acukids/homepage/index.html", "Locked": true, "StartPage": "homepage" },
    "OverrideFirstRunPage": "file:///opt/acukids/homepage/index.html",
    "NewTabPage": false,
    "BlockAboutConfig": true,
    "BlockAboutAddons": true,
    "BlockAboutProfiles": true,
    "BlockAboutSupport": true,
    "InstallAddonsPermission": { "Default": false },
    "Extensions": { "Install": [], "Uninstall": [], "Locked": [] },
    "WebsiteFilter": { "Block": ["<all_urls>"], "Exceptions": ${sites_json} }
  }
}
POLICY_EOF
  [[ -s "$staged" ]] || { rm -f "$staged"; return 1; }
  jq empty "$staged" >/dev/null 2>&1 || { rm -f "$staged"; return 1; }
  chmod 0644 "$staged" && mv -f "$staged" /etc/firefox/policies/policies.json || { rm -f "$staged"; return 1; }
}

apply_app_whitelist() {
  local apps_file="$CONFIG_DIR/whitelist-apps.conf"
  local blacklist_file="$CONFIG_DIR/blacklist-apps.conf"
  local children_file="$CONFIG_DIR/children.json"
  [[ -f "$apps_file" && -f "$children_file" ]] || return 0

  mapfile -t whitelist < <(grep -v '^\s*#' "$apps_file" | grep -v '^\s*$')
  mapfile -t blacklist < <([[ -f "$blacklist_file" ]] && grep -v '^\s*#' "$blacklist_file" | grep -v '^\s*$' || true)
  # Keep the built-in child logout action available even when an older
  # deployment's preserved whitelist predates this launcher.
  whitelist+=("acukids-done.desktop")
  mapfile -t children < <(jq -er '.[].username' "$children_file" 2>/dev/null) || return 1

  for cname in "${children[@]}"; do
    local home
    home=$(getent passwd "$cname" | cut -d: -f6) || return 1
    [[ -d "$home" ]] || return 1
    install -d -m 0755 "$home/.local/share/applications" || return 1
    find "$home/.local/share/applications" -maxdepth 1 -name '*.desktop' -delete 2>/dev/null || return 1

    shopt -s nullglob
    for desktop_file in /usr/share/applications/*.desktop /var/lib/snapd/desktop/applications/*.desktop; do
      local base
      base=$(basename "$desktop_file")
      local keep=0
      for w in "${whitelist[@]}"; do [[ "$base" == "$w" ]] && keep=1 && break; done
      for b in "${blacklist[@]}"; do [[ "$base" == "$b" ]] && keep=0 && break; done
      if [[ $keep -eq 0 ]]; then
        local staged
        staged=$(mktemp "$home/.local/share/applications/.acukids-hide.XXXXXX") || return 1
        cat > "$staged" << HIDE_EOF
[Desktop Entry]
Type=Application
Name=Hidden
NoDisplay=true
HIDE_EOF
        chmod 0644 "$staged" && mv -f "$staged" "$home/.local/share/applications/$base" || { rm -f "$staged"; return 1; }
        [[ -s "$home/.local/share/applications/$base" ]] || return 1
      fi
    done
    shopt -u nullglob
    chown -R "$cname:$cname" "$home/.local/share/applications" || return 1
  done
}

apply_time_limits() {
  local children_file="$CONFIG_DIR/children.json"
  [[ -f "$children_file" ]] || return 0
  local defaults_file="$CONFIG_DIR/timekpr-defaults.conf"
  [[ -f "$defaults_file" ]] || return 1
  command -v timekpra &>/dev/null || return 1

  local default_weekday default_weekend default_start default_end
  default_weekday=$(sed -n 's/^WEEKDAY_LIMIT_SECONDS=//p' "$defaults_file")
  default_weekend=$(sed -n 's/^WEEKEND_LIMIT_SECONDS=//p' "$defaults_file")
  default_start=$(sed -n 's/^ALLOWED_WINDOW_START=//p' "$defaults_file")
  default_end=$(sed -n 's/^ALLOWED_WINDOW_END=//p' "$defaults_file")
  [[ -n "$default_weekday" && -n "$default_weekend" && -n "$default_start" && -n "$default_end" ]] || return 1

  local count
  count=$(jq -er 'length' "$children_file" 2>/dev/null) || return 1
  for (( i=0; i<count; i++ )); do
    local cname weekday weekend window
    cname=$(jq -r ".[$i].username" "$children_file")
    weekday=$(jq -r --argjson fallback "$default_weekday" ".[$i].weekday_limit_seconds // \$fallback" "$children_file") || return 1
    weekend=$(jq -r --argjson fallback "$default_weekend" ".[$i].weekend_limit_seconds // \$fallback" "$children_file") || return 1
    window=$(jq -r --arg fallback "${default_start}-${default_end}" ".[$i].allowed_window // \$fallback" "$children_file") || return 1
    id "$cname" &>/dev/null || continue
    prepare_child_user_dirs "$cname" || return 1

    timekpra --settimelimits "$cname" "${weekday};${weekday};${weekday};${weekday};${weekday};${weekend};${weekend}" 2>/dev/null || return 1

    local start end start_min end_min
    start="${window%-*}"; end="${window#*-}"
    # Keep the minute components (not total minutes) for per-hour ranges.
    start_min=$((10#${start##*:}))
    end_min=$((10#${end##*:}))
    local start_hour end_hour allowed_hours hour token
    start_hour=$((10#${start%%:*})); end_hour=$((10#${end%%:*}))
    allowed_hours=""
    for (( hour=start_hour; hour<end_hour || (hour == end_hour && end_min > 0); hour++ )); do
      token="$hour"
      if (( hour == start_hour && start_min > 0 )); then token+="[${start_min}-59]"; fi
      if (( hour == end_hour && end_min > 0 )); then token+="[00-$((end_min - 1))]"; fi
      [[ -n "$allowed_hours" ]] && allowed_hours+=";"
      allowed_hours+="$token"
    done
    [[ -n "$allowed_hours" ]] || return 1
    timekpra --setalloweddays "$cname" "1;2;3;4;5;6;7" 2>/dev/null || return 1
    timekpra --setallowedhours "$cname" "ALL" "$allowed_hours" 2>/dev/null || return 1
    timekpra --setlockouttype "$cname" "lock" 2>/dev/null || return 1
  done
}

apply_accounts() {
  local children_file="$CONFIG_DIR/children.json"
  [[ -f "$children_file" ]] || return 0
  local count
  count=$(jq -er 'length' "$children_file" 2>/dev/null) || return 1
  getent group "$CHILD_GROUP" >/dev/null || groupadd "$CHILD_GROUP" || return 1
  for (( i=0; i<count; i++ )); do
    local cname
    cname=$(jq -r ".[$i].username" "$children_file")
    if ! id "$cname" &>/dev/null; then
      printf 'Account %s is missing; use acukids-manage.sh add-child to provision it with a PIN.\n' "$cname" >&2
      return 1
    else
      if ! getent group "$CHILD_GROUP" | grep -qw -- "$cname"; then
        printf 'Account conflict: existing user %s is not an acuKids-managed child.\n' "$cname" >&2
        return 1
      fi
      usermod -aG "$CHILD_GROUP" "$cname" || return 1
    fi
  done
}

apply_admin_account() {
  local meta="$CONFIG_DIR/system-meta.json" admin
  [[ -f "$meta" ]] || return 1
  admin=$(jq -er '.admin_account' "$meta") || return 1
  id "$admin" &>/dev/null || { printf 'Configured admin account does not exist: %s\n' "$admin" >&2; return 1; }
  usermod -aG sudo "$admin" || return 1
  getent group acukids-admin >/dev/null 2>&1 || groupadd acukids-admin || return 1
  usermod -aG acukids-admin "$admin" || return 1
}

prepare_child_user_dirs() {
  local cname="$1" home
  home=$(getent passwd "$cname" | cut -d: -f6) || return 1
  [[ -n "$home" && -d "$home" ]] || return 1
  install -d -m 0755 "$home/.config" "$home/.config/environment.d" "$home/.local" "$home/.local/share" "$home/.local/share/applications" "$home/.local/share/keyrings" || return 1
  chown "$cname:$cname" "$home/.config" "$home/.config/environment.d" "$home/.local" "$home/.local/share" "$home/.local/share/applications" "$home/.local/share/keyrings" || return 1
  touch "$home/.config/gnome-initial-setup-done" || return 1
  chown "$cname:$cname" "$home/.config/gnome-initial-setup-done" || return 1
}

apply_dconf_profiles() {
  local children_file="$CONFIG_DIR/children.json" cname home staged children
  [[ -f "$children_file" ]] || return 1
  children=$(jq -er '.[].username' "$children_file") || return 1
  while IFS= read -r cname || [[ -n "$cname" ]]; do
    prepare_child_user_dirs "$cname" || return 1
    home=$(getent passwd "$cname" | cut -d: -f6) || return 1
    [[ -n "$home" && -d "$home" ]] || return 1
    install -d -m 0755 "$home/.config/environment.d" || return 1
    staged=$(mktemp "$home/.config/environment.d/.acukids-dconf.XXXXXX") || return 1
    printf 'DCONF_PROFILE=%s\n' "$DCONF_PROFILE_NAME" > "$staged" || { rm -f "$staged"; return 1; }
    chmod 0644 "$staged" && mv -f "$staged" "$home/.config/environment.d/90-acukids-dconf.conf" || { rm -f "$staged"; return 1; }
    chown "$cname:$cname" "$home/.config/environment.d/90-acukids-dconf.conf" || return 1
  done <<< "$children"
}

apply_homepage() {
  local index="$ACUKIDS_HOME/homepage/index.html" marker="$ACUKIDS_HOME/homepage/.acukids-generated.sha256"
  [[ -f "$index" ]] || return 1
  local hash; hash=$(sha256sum "$index" | awk '{print $1}') || return 1
  grep -qxF "$hash  index.html" "$marker" 2>/dev/null || return 0
  local staged label url link
  staged=$(mktemp "$ACUKIDS_HOME/homepage/.index.html.XXXXXX") || return 1
  cat > "$staged" <<'EOF'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>acuKids</title><style>body{font-family:sans-serif;background:#fef9e7;text-align:center;padding:40px}.brand{width:min(280px,60vw);height:auto}h1{color:#2e86c1;font-size:2.4em;margin:16px 0 0}.grid{display:flex;flex-wrap:wrap;justify-content:center;gap:24px;margin-top:40px}a.tile{display:block;width:220px;padding:24px;border-radius:20px;background:#fff;box-shadow:0 4px 10px rgba(0,0,0,.15);text-decoration:none;color:#333;font-size:1.4em;font-weight:bold}a.tile:hover{background:#d6eaf8}</style></head><body><img class="brand" src="acukids-logo.png" alt="acuKids" onerror="this.hidden=true"><h1>Welcome! What would you like to explore?</h1><div class="grid">
EOF
  while IFS= read -r link; do
    label=$(jq -r '.label' <<<"$link" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g') || { rm -f "$staged"; return 1; }
    url=$(jq -r '.url' <<<"$link" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g') || { rm -f "$staged"; return 1; }
    printf '<a class="tile" href="%s">%s</a>\n' "$url" "$label" >> "$staged"
  done < <(jq -c '.[]' "$CONFIG_DIR/homepage-links.json")
  printf '</div></body></html>\n' >> "$staged"
  chmod 0644 "$staged" && mv -f "$staged" "$index" || { rm -f "$staged"; return 1; }
  printf '%s  index.html\n' "$(sha256sum "$index" | awk '{print $1}')" > "$marker"
}

apply_all() {
  require_root
  local restored="${1:-}"
  APPLY_FAILURES=()
  if ! validate_config; then
    changelog "FAILED configuration preflight validation"
    printf 'acuKids configuration preflight failed; no system changes were made.\n' >&2
    return 1
  fi
  if [[ "$restored" != "--restored-state" ]]; then
    snapshot_previous_state || APPLY_FAILURES+=("snapshot")
  fi
  run_apply_step accounts apply_accounts
  run_apply_step admin apply_admin_account
  run_apply_step dconf_profiles apply_dconf_profiles
  run_apply_step dns apply_dns
  run_apply_step firefox apply_firefox_whitelist
  run_apply_step applications apply_app_whitelist
  run_apply_step homepage apply_homepage
  run_apply_step time_limits apply_time_limits
  run_apply_step dconf dconf update
  if (( ${#APPLY_FAILURES[@]} > 0 )); then
    changelog "FAILED to apply configuration (subsystems: ${APPLY_FAILURES[*]})"
    printf 'acuKids configuration was not applied successfully. Failed subsystems: %s\n' "${APPLY_FAILURES[*]}" >&2
    return 1
  fi
  if ! record_last_applied_state; then
    changelog "FAILED to record successfully applied configuration state"
    printf 'acuKids configuration was applied but could not be recorded for rollback.\n' >&2
    return 1
  fi
  if [[ "$restored" == "--restored-state" ]]; then
    changelog "Applied restored configuration from config/"
    echo "acuKids restored configuration applied successfully."
  elif [[ -f "$STATE_DIR/$TS/PARENT" ]]; then
    changelog "Applied configuration from config/ (rollback snapshot: $TS)"
    echo "acuKids configuration applied successfully. Rollback snapshot saved: $TS"
  else
    changelog "Applied initial configuration from config/"
    echo "acuKids configuration applied successfully."
  fi
}

if [[ "${ACUKIDS_LIBRARY_MODE:-false}" != "true" ]]; then
  case "${1:-}" in
    --rollback) rollback ;;
    "") apply_all ;;
    *) echo "Unknown apply command: $1" >&2; exit 2 ;;
  esac
fi
APPLY_SCRIPT_EOF
}

build_manage_script() {
  cat > "$ACUKIDS_HOME/scripts/acukids-manage.sh" << 'MANAGE_SCRIPT_EOF'
#!/usr/bin/env bash
#
# acukids-manage.sh - simple CLI for common acuKids admin tasks.
# Edits the canonical config under /opt/acukids/config/ then calls
# acukids-apply.sh so changes take effect immediately.
#
set -uo pipefail
ACUKIDS_HOME="${ACUKIDS_HOME:-/opt/acukids}"
CONFIG_DIR="$ACUKIDS_HOME/config"
CHILDREN_JSON="$CONFIG_DIR/children.json"
APPLY="$ACUKIDS_HOME/scripts/acukids-apply.sh"

LOCK_FILE="/run/lock/acukids.lock"
acquire_lock() {
  [[ "${ACUKIDS_LOCK_HELD:-false}" == "true" ]] && return 0
  install -d -m 0755 "$(dirname "$LOCK_FILE")" || { echo "Unable to create lock parent." >&2; exit 1; }
  exec 9>"$LOCK_FILE" || { echo "Unable to open acuKids lock." >&2; exit 1; }
  flock -n 9 || { echo "Another acuKids operation is already running; retry after it completes." >&2; exit 1; }
  export ACUKIDS_LOCK_HELD=true
}
require_root() { [[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }; acquire_lock; }

valid_username() { [[ "$1" =~ ^[a-z][-a-z0-9_]{2,31}$ ]]; }
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9.-]+(/[A-Za-z0-9._~:/?#@!\$%\&\(\)\*+,;=-]+)?$ ]]; }
valid_desktop_file() { [[ "$1" =~ ^[A-Za-z0-9._-]+\.desktop$ ]]; }
configured_child() { jq -e --arg u "$1" 'any(.[]; .username == $u)' "$CHILDREN_JSON" >/dev/null 2>&1; }
admin_username() { jq -er '.admin_account' "$CONFIG_DIR/system-meta.json"; }
fallback_username() { jq -r '.original_installer_account // empty' "$CONFIG_DIR/system-meta.json"; }
require_child() {
  local u="$1"
  valid_username "$u" || { echo "Invalid username: $u" >&2; exit 1; }
  configured_child "$u" || { echo "Not a configured acuKids child: $u" >&2; exit 1; }
}
replace_exact_line() {
  local file="$1" value="$2" tmp owner group mode
  owner=$(stat -c '%u' "$file") || return 1
  group=$(stat -c '%g' "$file") || return 1
  mode=$(stat -c '%a' "$file") || return 1
  tmp=$(mktemp "$file.tmp.XXXXXX") || return 1
  awk -v target="$value" '$0 != target' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp" && chown "$owner:$group" "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

usage() {
  cat << USAGE
Usage: $0 <command> [args]

Commands:
  add-child <username> <4-digit-pin>     Create a new child account
  remove-child <username>                Remove a child account (home kept)
  list-children                          Show configured child accounts
  reset-time <username>                  Reset today's time budget for a child
  set-pin <username> <4-digit-pin>       Change a child's login PIN
  add-site <domain>                      Add a domain to the browser whitelist
  remove-site <domain>                   Remove a domain from the whitelist
  add-homepage-link <id> <label> <url>   Add or replace a homepage tile
  remove-homepage-link <id>              Remove a tile and blacklist its ID
  add-app <desktop-file>                 Add an app to the visible app grid
  remove-app <desktop-file>              Remove an app from the visible grid
  hide-fallback-account <username>       Hide an account from the login picker
                                          (still usable by typing the username
                                          manually - use for the original
                                          installer/recovery account)
  show-fallback-account <username>       Reverse the above, show it again
USAGE
}

add_child() {
  require_root
  local u="$1" pin="$2"
  valid_username "$u" || { echo "Invalid username: $u" >&2; exit 1; }
  [[ "$pin" =~ ^[0-9]{4}$ ]] || { echo "PIN must be 4 digits."; exit 1; }
  id "$u" >/dev/null 2>&1 && { echo "An account already exists for username: $u" >&2; exit 1; }
  configured_child "$u" && { echo "Child is already configured: $u" >&2; exit 1; }
  local tmp backup
  tmp=$(mktemp "$CHILDREN_JSON.tmp.XXXXXX") || { echo "Could not stage child configuration." >&2; exit 1; }
  backup=$(mktemp "$CHILDREN_JSON.backup.XXXXXX") || { rm -f "$tmp"; echo "Could not prepare child configuration backup." >&2; exit 1; }
  cp -p "$CHILDREN_JSON" "$backup" || { rm -f "$tmp" "$backup"; echo "Could not back up child configuration." >&2; exit 1; }
  jq --arg u "$u" '. + [{"username":$u,"created":(now|todate),"weekday_limit_seconds":3600,"weekend_limit_seconds":7200,"allowed_window":"06:00-19:00"}]' \
    "$CHILDREN_JSON" > "$tmp" || { rm -f "$tmp"; echo "Could not update child configuration." >&2; exit 1; }
  chmod --reference="$backup" "$tmp" && chown --reference="$backup" "$tmp" || { rm -f "$tmp" "$backup"; echo "Could not preserve child configuration permissions." >&2; exit 1; }
  mv -f "$tmp" "$CHILDREN_JSON" || { rm -f "$tmp" "$backup"; echo "Could not install child configuration." >&2; exit 1; }
  if ! adduser --disabled-password --gecos "$u" "$u" >/dev/null 2>&1 || ! usermod -aG acukids-children "$u" || ! echo "$u:$pin" | chpasswd; then
    cp -p "$backup" "$CHILDREN_JSON"; deluser "$u" >/dev/null 2>&1 || true; rm -f "$backup"
    echo "Child account or PIN provisioning failed; configuration was rolled back." >&2; exit 1
  fi
  if ! "$APPLY"; then
    cp -p "$backup" "$CHILDREN_JSON"; "$APPLY" >/dev/null 2>&1 || true; deluser "$u" >/dev/null 2>&1 || true; rm -f "$backup"
    echo "Child configuration could not be applied; no child was retained." >&2; exit 1
  fi
  rm -f "$backup"
  echo "Child '$u' added with PIN set."
}

remove_child() {
  require_root
  local u="$1"
  require_child "$u"
  local tmp backup
  tmp=$(mktemp "$CHILDREN_JSON.tmp.XXXXXX") || { echo "Could not stage child configuration." >&2; exit 1; }
  backup=$(mktemp "$CHILDREN_JSON.backup.XXXXXX") || { rm -f "$tmp"; echo "Could not prepare child configuration backup." >&2; exit 1; }
  cp -p "$CHILDREN_JSON" "$backup" || { rm -f "$tmp" "$backup"; echo "Could not back up child configuration." >&2; exit 1; }
  jq --arg u "$u" 'map(select(.username != $u))' "$CHILDREN_JSON" > "$tmp" || { rm -f "$tmp" "$backup"; echo "Could not update child configuration." >&2; exit 1; }
  chmod --reference="$backup" "$tmp" && chown --reference="$backup" "$tmp" || { rm -f "$tmp" "$backup"; echo "Could not preserve child configuration permissions." >&2; exit 1; }
  mv -f "$tmp" "$CHILDREN_JSON" || { rm -f "$tmp" "$backup"; echo "Could not install child configuration." >&2; exit 1; }
  if ! "$APPLY"; then
    cp -p "$backup" "$CHILDREN_JSON"
    "$APPLY" >/dev/null 2>&1 || true
    rm -f "$backup"
    echo "Child configuration could not be applied; account was retained." >&2
    exit 1
  fi
  if ! deluser "$u" 2>/dev/null; then
    cp -p "$backup" "$CHILDREN_JSON"
    "$APPLY" >/dev/null 2>&1 || true
    rm -f "$backup"
    echo "Child account removal failed; configuration was restored." >&2
    exit 1
  fi
  rm -f "$backup"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Removed child account: $u (home directory preserved)" >> "$ACUKIDS_HOME/CHANGELOG.md"
  echo "Child '$u' removed from config (home directory kept at /home/$u)."
}

list_children() {
  jq -r '.[] | "\(.username)  weekday=\(.weekday_limit_seconds)s weekend=\(.weekend_limit_seconds)s window=\(.allowed_window)"' "$CHILDREN_JSON"
}

reset_time() {
  require_root
  local u="$1"
  require_child "$u"
  command -v timekpra &>/dev/null || { echo "timekpra is unavailable." >&2; exit 1; }
  local limit day
  day=$(date +%u)
  if (( day <= 5 )); then
    limit=$(jq -er --arg u "$u" '.[] | select(.username == $u) | .weekday_limit_seconds // 3600' "$CHILDREN_JSON") || { echo "Could not read weekday limit for $u." >&2; exit 1; }
  else
    limit=$(jq -er --arg u "$u" '.[] | select(.username == $u) | .weekend_limit_seconds // 7200' "$CHILDREN_JSON") || { echo "Could not read weekend limit for $u." >&2; exit 1; }
  fi
  timekpra --settimeleft "$u" "=" "$limit" 2>/dev/null || { echo "Could not reset time for $u." >&2; exit 1; }
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Reset today's time budget for $u" >> "$ACUKIDS_HOME/CHANGELOG.md"
  echo "Time budget reset for $u."
}

set_pin() {
  require_root
  local u="$1" pin="$2"
  require_child "$u"
  [[ "$pin" =~ ^[0-9]{4}$ ]] || { echo "PIN must be 4 digits."; exit 1; }
  echo "$u:$pin" | chpasswd || { echo "PIN update failed for $u." >&2; exit 1; }
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Changed PIN for $u" >> "$ACUKIDS_HOME/CHANGELOG.md"
  echo "PIN updated for $u."
}

add_site() {
  require_root
  local d="$1"
  valid_domain "$d" || { echo "Invalid domain/path: $d" >&2; exit 1; }
  local file="$CONFIG_DIR/whitelist-sites.conf" backup
  backup=$(mktemp "$file.backup.XXXXXX") || { echo "Could not prepare whitelist backup." >&2; exit 1; }
  cp -p "$file" "$backup" || { rm -f "$backup"; echo "Could not back up website whitelist." >&2; exit 1; }
  grep -qxF "$d" "$file" || echo "$d" >> "$file" || { rm -f "$backup"; echo "Could not update website whitelist." >&2; exit 1; }
  if ! "$APPLY"; then cp -p "$backup" "$file"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup"; echo "Website whitelist could not be applied; prior whitelist restored." >&2; exit 1; fi
  rm -f "$backup"
  echo "Added '$d' to browser whitelist."
}

remove_site() {
  require_root
  local d="$1"
  valid_domain "$d" || { echo "Invalid domain/path: $d" >&2; exit 1; }
  local file="$CONFIG_DIR/whitelist-sites.conf" backup
  backup=$(mktemp "$file.backup.XXXXXX") || { echo "Could not prepare whitelist backup." >&2; exit 1; }
  cp -p "$file" "$backup" || { rm -f "$backup"; echo "Could not back up website whitelist." >&2; exit 1; }
  replace_exact_line "$file" "$d" || { rm -f "$backup"; echo "Could not update website whitelist." >&2; exit 1; }
  if ! "$APPLY"; then cp -p "$backup" "$file"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup"; echo "Website whitelist could not be applied; prior whitelist restored." >&2; exit 1; fi
  rm -f "$backup"
  echo "Removed '$d' from browser whitelist."
}

valid_homepage_url() { [[ "$1" =~ ^https://[^[:space:]]+$ ]]; }

homepage_site_covered() {
  local url="$1" host path site
  host=$(sed -E 's#^https://([^/:?#]+).*#\1#' <<<"$url")
  path=$(sed -E 's#^https://[^/]+##' <<<"$url"); [[ -n "$path" ]] || path=/
  while IFS= read -r site || [[ -n "$site" ]]; do
    [[ -z "$site" || "$site" == \#* ]] && continue
    local shost spath
    shost="${site%%/*}"; spath="/${site#*/}"; [[ "$site" != */* ]] && spath="/"
    if [[ "$host" == "$shost" || "$host" == *".$shost" ]]; then
      [[ "$spath" == / || "$path" == "$spath" || "$path" == "$spath"/* ]] && return 0
    fi
  done < "$CONFIG_DIR/whitelist-sites.conf"
  return 1
}

add_homepage_link() {
  require_root; local id="$1" label="$2" url="$3" file="$CONFIG_DIR/homepage-links.json" tmp backup
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]{1,63}$ ]] || { echo "Invalid homepage link ID." >&2; exit 1; }
  [[ -n "$label" && ${#label} -le 120 ]] || { echo "Homepage label must be 1-120 characters." >&2; exit 1; }
  valid_homepage_url "$url" || { echo "Homepage URL must be an https URL." >&2; exit 1; }
  homepage_site_covered "$url" || { echo "Add a matching browser whitelist entry first." >&2; exit 1; }
  backup=$(mktemp "$file.backup.XXXXXX") || exit 1; cp -p "$file" "$backup" || exit 1
  tmp=$(mktemp "$file.tmp.XXXXXX") || exit 1
  jq --arg id "$id" --arg label "$label" --arg url "$url" 'map(select(.id != $id)) + [{id:$id,label:$label,url:$url}]' "$file" > "$tmp" || { rm -f "$tmp"; exit 1; }
  chmod --reference="$file" "$tmp" && chown --reference="$file" "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; exit 1; }
  replace_exact_line "$CONFIG_DIR/blacklist-homepage-links.conf" "$id" || true
  if ! "$APPLY"; then cp -p "$backup" "$file"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup"; exit 1; fi
  rm -f "$backup"; echo "Homepage link '$id' added."
}

remove_homepage_link() {
  require_root; local id="$1" file="$CONFIG_DIR/homepage-links.json" blacklist="$CONFIG_DIR/blacklist-homepage-links.conf" tmp backup
  [[ "$id" =~ ^[a-z0-9][a-z0-9-]{1,63}$ ]] || { echo "Invalid homepage link ID." >&2; exit 1; }
  backup=$(mktemp "$file.backup.XXXXXX") || exit 1; cp -p "$file" "$backup" || exit 1
  tmp=$(mktemp "$file.tmp.XXXXXX") || exit 1
  jq --arg id "$id" 'map(select(.id != $id))' "$file" > "$tmp" || { rm -f "$tmp"; exit 1; }
  chmod --reference="$file" "$tmp" && chown --reference="$file" "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; exit 1; }
  grep -qxF "$id" "$blacklist" || echo "$id" >> "$blacklist"
  if ! "$APPLY"; then cp -p "$backup" "$file"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup"; exit 1; fi
  rm -f "$backup"; echo "Homepage link '$id' removed and blacklisted."
}

add_app() {
  require_root
  local a="$1"
  valid_desktop_file "$a" || { echo "Invalid desktop filename: $a" >&2; exit 1; }
  local file="$CONFIG_DIR/whitelist-apps.conf" blacklist="$CONFIG_DIR/blacklist-apps.conf" backup blacklist_backup
  backup=$(mktemp "$file.backup.XXXXXX") || { echo "Could not prepare app whitelist backup." >&2; exit 1; }
  blacklist_backup=$(mktemp "$blacklist.backup.XXXXXX") || { rm -f "$backup"; echo "Could not prepare app blacklist backup." >&2; exit 1; }
  cp -p "$file" "$backup" || { rm -f "$backup"; echo "Could not back up application whitelist." >&2; exit 1; }
  [[ -e "$blacklist" ]] || printf '# Apps explicitly rejected by the owner.\n' > "$blacklist"
  cp -p "$blacklist" "$blacklist_backup" || { rm -f "$backup" "$blacklist_backup"; echo "Could not back up application blacklist." >&2; exit 1; }
  grep -qxF "$a" "$file" || echo "$a" >> "$file" || { rm -f "$backup"; echo "Could not update application whitelist." >&2; exit 1; }
  replace_exact_line "$blacklist" "$a" || true
  if ! "$APPLY"; then cp -p "$backup" "$file"; cp -p "$blacklist_backup" "$blacklist"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup" "$blacklist_backup"; echo "Application whitelist could not be applied; prior whitelist restored." >&2; exit 1; fi
  rm -f "$backup" "$blacklist_backup"
  echo "Added '$a' to visible app grid."
}

remove_app() {
  require_root
  local a="$1"
  valid_desktop_file "$a" || { echo "Invalid desktop filename: $a" >&2; exit 1; }
  local file="$CONFIG_DIR/whitelist-apps.conf" blacklist="$CONFIG_DIR/blacklist-apps.conf" backup blacklist_backup
  backup=$(mktemp "$file.backup.XXXXXX") || { echo "Could not prepare app whitelist backup." >&2; exit 1; }
  blacklist_backup=$(mktemp "$blacklist.backup.XXXXXX") || { rm -f "$backup"; echo "Could not prepare app blacklist backup." >&2; exit 1; }
  cp -p "$file" "$backup" || { rm -f "$backup"; echo "Could not back up application whitelist." >&2; exit 1; }
  [[ -e "$blacklist" ]] || printf '# Apps explicitly rejected by the owner.\n' > "$blacklist"
  cp -p "$blacklist" "$blacklist_backup" || { rm -f "$backup" "$blacklist_backup"; echo "Could not back up application blacklist." >&2; exit 1; }
  replace_exact_line "$file" "$a" || true
  grep -qxF "$a" "$blacklist" || echo "$a" >> "$blacklist" || { rm -f "$backup" "$blacklist_backup"; echo "Could not update application blacklist." >&2; exit 1; }
  if ! "$APPLY"; then cp -p "$backup" "$file"; cp -p "$blacklist_backup" "$blacklist"; "$APPLY" >/dev/null 2>&1 || true; rm -f "$backup" "$blacklist_backup"; echo "Application whitelist could not be applied; prior whitelist restored." >&2; exit 1; fi
  rm -f "$backup" "$blacklist_backup"
  echo "Removed '$a' from visible app grid."
}

set_account_visibility() {
  require_root
  local u="$1" hidden="$2"  # hidden: true or false
  valid_username "$u" || { echo "Invalid username: $u" >&2; exit 1; }
  [[ "$u" == "$(fallback_username)" ]] || { echo "Visibility operations are limited to the recorded fallback account." >&2; exit 1; }
  id "$u" &>/dev/null || { echo "No such account: $u" >&2; exit 1; }
  install -d /var/lib/AccountsService/users
  local f="/var/lib/AccountsService/users/$u"
  if [[ -f "$f" ]]; then
    if grep -q "^SystemAccount=" "$f"; then
      sed -i "s/^SystemAccount=.*/SystemAccount=${hidden}/" "$f"
    else
      if grep -q "^\[User\]" "$f"; then
        sed -i "/^\[User\]/a SystemAccount=${hidden}" "$f"
      else
        printf '[User]\nSystemAccount=%s\n' "$hidden" >> "$f"
      fi
    fi
  else
    printf '[User]\nSystemAccount=%s\n' "$hidden" > "$f"
  fi
  local meta_tmp meta_backup accounts_backup accounts_existed=false
  meta_tmp=$(mktemp "$CONFIG_DIR/system-meta.json.tmp.XXXXXX") || { echo "Could not stage visibility metadata." >&2; exit 1; }
  meta_backup=$(mktemp "$CONFIG_DIR/system-meta.json.backup.XXXXXX") || { rm -f "$meta_tmp"; echo "Could not back up visibility metadata." >&2; exit 1; }
  cp -p "$CONFIG_DIR/system-meta.json" "$meta_backup" || { rm -f "$meta_tmp" "$meta_backup"; echo "Could not back up visibility metadata." >&2; exit 1; }
  accounts_backup=$(mktemp "$f.backup.XXXXXX") || { rm -f "$meta_tmp" "$meta_backup"; echo "Could not back up account visibility state." >&2; exit 1; }
  if [[ -f "$f" ]]; then accounts_existed=true; cp -p "$f" "$accounts_backup" || { rm -f "$meta_tmp" "$meta_backup" "$accounts_backup"; echo "Could not back up account visibility state." >&2; exit 1; }; fi
  jq --argjson hidden "$hidden" '.original_installer_account_hidden = $hidden' "$CONFIG_DIR/system-meta.json" > "$meta_tmp" || { rm -f "$meta_tmp" "$meta_backup"; echo "Could not update visibility metadata." >&2; exit 1; }
  chmod --reference="$meta_backup" "$meta_tmp" && chown --reference="$meta_backup" "$meta_tmp" || { rm -f "$meta_tmp" "$meta_backup" "$accounts_backup"; echo "Could not preserve metadata permissions." >&2; exit 1; }
  mv -f "$meta_tmp" "$CONFIG_DIR/system-meta.json" || { rm -f "$meta_tmp" "$meta_backup"; echo "Could not install visibility metadata." >&2; exit 1; }
  if ! systemctl restart accounts-daemon 2>/dev/null; then
    cp -p "$meta_backup" "$CONFIG_DIR/system-meta.json"
    if [[ "$accounts_existed" == "true" ]]; then cp -p "$accounts_backup" "$f"; else rm -f "$f"; fi
    rm -f "$meta_backup" "$accounts_backup"
    echo "Could not refresh account visibility; metadata was restored." >&2
    exit 1
  fi
  rm -f "$meta_backup" "$accounts_backup"
  if [[ "$hidden" == "true" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Hid account '$u' from the login picker" >> "$ACUKIDS_HOME/CHANGELOG.md"
    echo "'$u' is now hidden from the login screen's user list. It still works as a login if the username is typed manually (click 'Not listed?' on GDM, or just type the name)."
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Restored account '$u' to the login picker" >> "$ACUKIDS_HOME/CHANGELOG.md"
    echo "'$u' will appear in the login picker again."
  fi
}

if [[ "${ACUKIDS_LIBRARY_MODE:-false}" != "true" ]]; then
  case "${1:-}" in
    add-child)     add_child "${2:?username required}" "${3:?pin required}" ;;
    remove-child)  remove_child "${2:?username required}" ;;
    list-children) list_children ;;
    reset-time)    reset_time "${2:?username required}" ;;
    set-pin)       set_pin "${2:?username required}" "${3:?pin required}" ;;
    add-site)      add_site "${2:?domain required}" ;;
    remove-site)   remove_site "${2:?domain required}" ;;
    add-homepage-link) add_homepage_link "${2:?id required}" "${3:?label required}" "${4:?url required}" ;;
    remove-homepage-link) remove_homepage_link "${2:?id required}" ;;
    add-app)       add_app "${2:?desktop file required}" ;;
    remove-app)    remove_app "${2:?desktop file required}" ;;
    hide-fallback-account) set_account_visibility "${2:?username required}" "true" ;;
    show-fallback-account) set_account_visibility "${2:?username required}" "false" ;;
    "") usage; exit 2 ;;
    *) echo "Unknown manage command: $1" >&2; usage >&2; exit 2 ;;
  esac
fi
MANAGE_SCRIPT_EOF
}

build_changelog() {
  if [[ -e "$ACUKIDS_HOME/CHANGELOG.md" ]]; then
    echo "- $(date '+%Y-%m-%d %H:%M:%S') - Reconciled existing acuKids deployment (version $SCRIPT_VERSION)" >> "$ACUKIDS_HOME/CHANGELOG.md"
    return 0
  fi
  cat > "$ACUKIDS_HOME/CHANGELOG.md" << CHANGELOG_EOF
# acuKids Changelog

Append-only record of deployment and configuration changes. Entries are
added automatically by acukids-deploy.sh and acukids-apply.sh.

- $(date '+%Y-%m-%d %H:%M:%S') - Initial acuKids deployment (version $SCRIPT_VERSION) on host $ACUKIDS_HOSTNAME
CHANGELOG_EOF
}

# ---------------------------------------------------------------------------
# Step 11: Finalize
# ---------------------------------------------------------------------------
step_finalize() {
  log "=== Step 11: Finalizing ==="
  apt-get -y autoremove >> "$LOG_FILE" 2>&1 || true

  echo
  echo "======================================================================"
  echo " acuKids deployment complete!"
  echo "======================================================================"
  echo "Hostname:            $ACUKIDS_HOSTNAME"
  echo "Admin login:         $ADMIN_USERNAME"
  echo "Child logins:        ${CHILD_USERNAMES[*]} (4-digit PIN each)"
  echo "Fallback login:      ${ORIGINAL_ADMIN_USER:-<none>} (kept, auto-login off)"
  echo "Control repo:        $ACUKIDS_HOME  (see AGENTS.md / CLAUDE.md)"
  echo "Manage children:     sudo $ACUKIDS_HOME/scripts/acukids-manage.sh"
  echo "Full log:            $LOG_FILE"
  if (( ${#OPTIONAL_FAILURES[@]} > 0 )); then
    echo "Optional components needing follow-up: ${OPTIONAL_FAILURES[*]}"
    log "Optional components needing follow-up: ${OPTIONAL_FAILURES[*]}"
  fi
  echo
  echo "A reboot is required to finalize account/desktop/browser changes."
  echo "======================================================================"
  read -r -p "Reboot now? [Y/n]: " reboot_ans
  if [[ "${reboot_ans,,}" != "n" ]]; then
    log "Rebooting now."
    reboot
  else
    log "Reboot deferred by user. Please reboot manually before use."
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "acuKids deployment script build $SCRIPT_BUILD (release $SCRIPT_VERSION)"
  require_root
  acquire_lock
  ensure_interactive_stdin
  : > "$LOG_FILE"
  log "acuKids deployment script build $SCRIPT_BUILD (release $SCRIPT_VERSION)"
  if [[ -f "$ACUKIDS_HOME/config/system-meta.json" && -f "$ACUKIDS_HOME/config/children.json" ]]; then
    EXISTING_DEPLOYMENT=true
  fi
  require_ubuntu_2604
  check_ram
  require_internet
  gather_configuration
  validate_existing_configuration
  if [[ "$EXISTING_DEPLOYMENT" == "false" && "$INTERRUPTED_INSTALL" == "false" ]]; then
    write_install_state
  fi

  step_system_prep
  step_accounts
  step_edu_software
  if [[ "$RERUN_MODE" == "false" ]]; then
    step_browsers
    step_dns_filtering
    step_time_limits
    step_desktop_lockdown
  else
    log "Skipping fresh-install browser writes; reconciling preserved DNS, time limits, and desktop lockdown."
    step_desktop_lockdown
  fi
  step_unattended_upgrades
  step_agentic_harnesses
  step_build_repo
  if [[ "$RERUN_MODE" == "true" ]]; then
    recovery_dir="$ACUKIDS_HOME/state/script-recovery-$(date '+%Y%m%d-%H%M%S-%N')"
    install -d -m 0755 "$recovery_dir" || die "Could not create script recovery copy."
    cp -a "$ACUKIDS_HOME/scripts/acukids-apply.sh" "$ACUKIDS_HOME/scripts/acukids-manage.sh" "$recovery_dir/" || die "Could not save script recovery copy."
    bash -n "$ACUKIDS_HOME/scripts/acukids-apply.sh" "$ACUKIDS_HOME/scripts/acukids-manage.sh" || die "Owner-edited acuKids script failed syntax validation; no reconciliation was attempted. Restore it from local Git history and rerun."
    "$ACUKIDS_HOME/scripts/acukids-apply.sh" || die "Existing acuKids configuration reconciliation failed."
  fi
  [[ "$INTERRUPTED_INSTALL" != "true" ]] || rm -f "$INSTALL_STATE_FILE"
  step_finalize
}

if [[ "${ACUKIDS_LIBRARY_MODE:-false}" != "true" ]]; then
  main "$@"
fi
