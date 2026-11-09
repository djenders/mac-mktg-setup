#!/usr/bin/env bash
#
# day-one.sh — run on the NEW machine, after Homebrew is installed.
#
#   cd ~/Developer/mac-mktg-setup/install
#   bash day-one.sh
#
# Asks before each tier. Safe to re-run — brew bundle is idempotent, so if
# something fails halfway you just run it again.

if [ -z "${BASH_VERSION:-}" ]; then exec /usr/bin/env bash "$0" "$@"; fi
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then :
elif [ -d "$SCRIPT_DIR/../brewfiles" ]; then REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
else REPO="$PWD"; fi
BF="$REPO/brewfiles"

BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'; DIM=$'\033[2m'; OFF=$'\033[0m'
say()  { printf "\n${BLUE}==>${OFF} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✓${OFF} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${OFF} %s\n" "$*"; }
die()  { printf "  ${RED}✗${OFF} %s\n" "$*"; }

ask() {
  printf "\n${YELLOW}?${OFF} %s ${DIM}[y/N]${OFF} " "$1"
  a=""
  if [ -r /dev/tty ]; then
    read -r a </dev/tty || a=""
  else
    read -r a || a=""
  fi
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

printf "\n${BLUE}day-one.sh${OFF}  ${DIM}%s · macOS %s${OFF}\n" \
  "$(scutil --get ComputerName 2>/dev/null || hostname)" \
  "$(sw_vers -productVersion 2>/dev/null)"
printf "  repo  %s\n" "$REPO"

# ---------------------------------------------------------------------------
say "Preflight"

if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew not on PATH. Install it, then:"
  die "  eval \"\$(/opt/homebrew/bin/brew shellenv)\""
  exit 1
fi
ok "brew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"

if [ ! -d "$BF" ]; then
  die "No brewfiles/ at $BF — is the repo complete?"
  exit 1
fi
ok "brewfiles found"

# Put brew on PATH permanently if it isn't already
if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
  printf '\neval "$(/opt/homebrew/bin/brew shellenv)"\n' >> "$HOME/.zprofile"
  ok "added brew to ~/.zprofile"
fi

MACOS="$(sw_vers -productVersion 2>/dev/null)"
case "$MACOS" in
  27.3*|27.4*) warn "You're on a beta ($MACOS). 27.2 is the stable release." ;;
esac

# ---------------------------------------------------------------------------
say "App tiers"

install_tier() {
  tier="$1"; label="$2"
  file="$BF/Brewfile.$tier"
  [ -f "$file" ] || { warn "missing $file — skipped"; return; }
  n=$(grep -cE '^(brew|cask|mas) ' "$file" 2>/dev/null || echo 0)
  ask "Install $label  ${DIM}($n entries)${OFF}" || { printf "  skipped\n"; return; }
  if brew bundle install --file="$file"; then
    ok "$label done"
  else
    die "$label had failures — re-run this script to retry just that tier"
  fi
}

install_tier core     "CORE      shell, browsers, utilities, comms"
install_tier creative "CREATIVE  Adobe CC, Framer"
install_tier media    "MEDIA     Roon, TIDAL, readers, Steam"
install_tier ai       "AI        Docker, LM Studio, Draw Things"
install_tier finance  "FINANCE   Ledger"

printf "\n${YELLOW}!${OFF} WORK tier: check System Settings → Privacy & Security →\n"
printf "  Profiles first. If GMR's MDM manages Office/Teams/Webex, skip this —\n"
printf "  MDM will push them and your Brewfile will fight it.\n"
install_tier work "WORK      Office, Teams, Webex, Zoom, OneDrive"

# ---------------------------------------------------------------------------
say "Mac App Store"
if command -v mas >/dev/null 2>&1; then
  warn "Sign into the App Store app before this works."
  if ask "Install App Store apps now?"; then
    brew bundle install --file="$BF/Brewfile.core" 2>/dev/null
    ok "mas entries attempted (re-run after signing in if any failed)"
  fi
else
  warn "mas not installed yet — it comes with Brewfile.core"
fi

# ---------------------------------------------------------------------------
say "GitHub"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    ok "already authenticated"
  elif ask "Authenticate GitHub CLI?"; then
    gh auth login
  fi
else
  warn "gh not installed — 'brew install gh' then 'gh auth login'"
fi

# ---------------------------------------------------------------------------
say "SSH key"
if [ -f "$HOME/.ssh/id_ed25519" ]; then
  ok "key already exists — not touching it"
elif ask "Generate a NEW SSH key? (recommended — don't copy the old one)"; then
  ssh-keygen -t ed25519 -C "dennis@jenders.com" -f "$HOME/.ssh/id_ed25519"
  ok "created ~/.ssh/id_ed25519"
  printf "\n  Public key — add to GitHub and the NAS:\n\n"
  cat "$HOME/.ssh/id_ed25519.pub"
  printf "\n"
  if ask "Add it to GitHub now?"; then
    gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --title "$(scutil --get ComputerName 2>/dev/null || hostname)"
  fi
fi

if [ ! -f "$HOME/.ssh/config" ] && ask "Add a 'Mnemosyne' SSH alias for the NAS?"; then
  printf '\nHost Mnemosyne mnemosyne\n    HostName 192.168.1.76\n' >> "$HOME/.ssh/config"
  chmod 600 "$HOME/.ssh/config"
  ok "~/.ssh/config — add your NAS username under User"
fi

# ---------------------------------------------------------------------------
say "What's left — none of this can be scripted"
cat <<'CHECKLIST'

  ORDER MATTERS on the first two.

  1. ADOBE, then FONTS
       a. open Creative Cloud, sign in
       b. let Adobe Fonts finish syncing
       c. ONLY THEN restore fonts from the archive — or better, don't:
          start at zero and pull families out of fonts-user.tar.gz on demand
       d. Font Book → File → Validate Fonts

  2. OBSIDIAN
       a. install app, sign into Sync FIRST
       b. then restore the vault
       c. check the plugin list against manifests/obsidian.md
          (Sync's settings/plugin toggle is per-vault and easy to miss)

  3. MODELS — point these at external storage BEFORE downloading anything
       LM Studio        Settings → Models directory
       Stability Matrix portable — place the data folder where you want it
       Draw Things      Settings → model storage location

  4. INTEL APP AUDIT
       System Settings → General → About → Intel-Based Apps → Details
       Everything listed dies with macOS 28, ~Sept 2027.

  5. RE-PAIR
       Tailscale · UniFi · Sonos · Roon remote · printer · Logitech

  6. DO NOT INSTALL EVERNOTE
       Free accounts get one device. Daedalus holds that slot and is the
       only machine that can export .enex. Leave it that way.

  7. IN TWO WEEKS
       cd capture && ./capture.sh
       git diff manifests/
       Whatever shows up is what you rebuilt by hand and forgot to write
       down. Fold it into the Brewfiles. That diff is the whole point.

CHECKLIST

say "Done"
printf "  Daedalus stays intact for 30 days. Pull anything you missed.\n\n"
