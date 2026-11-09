#!/usr/bin/env bash
#
# capture.sh — run this BEFORE you wipe.
#
#   ./capture.sh                      # everything
#   ./capture.sh brew fonts obsidian  # named sections only
#   ./capture.sh --where              # print paths and exit, touch nothing
#   ./capture.sh --debug brew         # trace every command
#
# Sections: brew fonts obsidian evernote browsers dotfiles vscode defaults
#           creative models secrets
#
# Writes to two places, and says which before it starts:
#   repo    → manifests/ brewfiles/ config/   (safe to commit)
#   archive → $ARCHIVE_ROOT                    (never commit)

# macOS's /bin/sh is bash 3.2 in POSIX mode and chokes on parts of this.
# If we weren't started by bash, restart under bash.
if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -uo pipefail

# ------------------------------------------------------------------------------
# Flags
# ------------------------------------------------------------------------------

DEBUG=0
WHERE_ONLY=0
SECTIONS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)   DEBUG=1 ;;
    --where)   WHERE_ONLY=1 ;;
    -h|--help) sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         SECTIONS+=("$1") ;;
  esac
  shift
done

[ "$DEBUG" -eq 1 ] && set -x

# ------------------------------------------------------------------------------
# Where are we writing? Resolve loudly, before anything else.
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  :
elif [ -f "$SCRIPT_DIR/../README.md" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -f "$SCRIPT_DIR/README.md" ]; then
  REPO_ROOT="$SCRIPT_DIR"
else
  REPO_ROOT="$PWD"
fi

STAMP="$(date +%Y-%m-%d)"
ARCHIVE_ROOT="${ARCHIVE_ROOT:-$HOME/Desktop/mac-restore-$STAMP}"

MANIFESTS="$REPO_ROOT/manifests"
BREWFILES="$REPO_ROOT/brewfiles"
CONFIG="$REPO_ROOT/config"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BLUE=$'\033[0;34m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'; DIM=$'\033[2m'; OFF=$'\033[0m'
say()  { printf "\n${BLUE}==>${OFF} %s\n" "$*"; }
ok()   { printf "  ${GREEN}✓${OFF} %s\n" "$*"; }
warn() { printf "  ${YELLOW}!${OFF} %s\n" "$*"; }
skip() { printf "  ${DIM}–${OFF} %s\n" "$*"; }
die()  { printf "  ${RED}✗${OFF} %s\n" "$*"; }

printf "\n%scapture.sh%s  %sbash %s · macOS %s%s\n\n" \
  "$BLUE" "$OFF" "$DIM" "${BASH_VERSION%%(*}" "$(sw_vers -productVersion 2>/dev/null)" "$OFF"
printf "  script     %s\n" "$SCRIPT_DIR"
printf "  repo root  %s\n" "$REPO_ROOT"
printf "  archive    %s\n" "$ARCHIVE_ROOT"
printf "  sections   %s\n\n" "${SECTIONS[*]:-all}"

if [ "$WHERE_ONLY" -eq 1 ]; then
  echo "  (--where: nothing written)"
  exit 0
fi

if [ "$REPO_ROOT" = "$HOME" ]; then
  die "Repo root resolved to your home directory — that's not right."
  die "This script expects to live inside the repo at <repo>/capture/capture.sh."
  die "Move it there, or cd into the repo checkout and run it from within."
  exit 1
fi

mkdir -p "$MANIFESTS" "$BREWFILES" "$CONFIG" "$ARCHIVE_ROOT"

# bash 3.2 safe: never expand a possibly-empty array bare under `set -u`
want() {
  [ ${#SECTIONS[@]} -eq 0 ] && return 0
  local s
  for s in "${SECTIONS[@]}"; do [ "$s" = "$1" ] && return 0; done
  return 1
}

# ------------------------------------------------------------------------------
# 1. Homebrew
# ------------------------------------------------------------------------------

if want brew; then
  say "Homebrew"

  if ! command -v brew >/dev/null 2>&1; then
    die "brew is not on PATH for this shell."
    die "Apple silicon installs to /opt/homebrew. Try:"
    die "  eval \"\$(/opt/homebrew/bin/brew shellenv)\" && ./capture.sh brew"
  else
    ok "brew $(brew --version 2>/dev/null | head -1 | awk '{print $2}') at $(command -v brew)"

    if brew bundle dump --describe --force --file="$BREWFILES/Brewfile.captured"; then
      ok "brewfiles/Brewfile.captured"
      for K in tap brew cask mas vscode; do
        C=$(grep -cE "^$K " "$BREWFILES/Brewfile.captured" 2>/dev/null || true)
        [ "${C:-0}" -gt 0 ] && printf "      %-7s %s\n" "$K" "$C"
      done
      warn "Split into brewfiles/Brewfile.{core,creative,media,ai,work}"
    else
      die "brew bundle dump failed. Run it by hand to see why:"
      die "  brew bundle dump --describe --force --file=/tmp/Brewfile"
    fi

    brew leaves      > "$MANIFESTS/brew-leaves.txt" 2>/dev/null && ok "manifests/brew-leaves.txt"
    brew list --cask > "$MANIFESTS/brew-casks.txt"  2>/dev/null && ok "manifests/brew-casks.txt"

    # --- Orphan apps: one brew call, not one per cask -------------------------
    if brew info --installed --json=v2 > "$WORK/brew.json" 2>/dev/null; then
      python3 - "$WORK/brew.json" > "$WORK/managed.txt" <<'PY'
import json, sys
apps = set()
def strip(s): return s[:-4] if s.endswith(".app") else s
for cask in json.load(open(sys.argv[1])).get("casks", []):
    for art in cask.get("artifacts", []):
        if not isinstance(art, dict):
            continue
        for entry in art.get("app", []) or []:
            if isinstance(entry, str):
                apps.add(strip(entry))
            elif isinstance(entry, dict):
                for v in entry.values():
                    if isinstance(v, str):
                        apps.add(strip(v))
print("\n".join(sorted(apps)))
PY
      ls -1 /Applications 2>/dev/null | sed 's/\.app$//' | sort -u > "$WORK/installed.txt"
      sort -u -o "$WORK/managed.txt" "$WORK/managed.txt"
      {
        echo "# Apps in /Applications that Homebrew does not manage — $STAMP"
        echo "#"
        echo "# Each needs one of: a cask in a Brewfile, a mas entry, a line in"
        echo "# docs/MANUAL.md, or an honest admission you don't use it."
        echo "# Apple built-ins (Mail, Safari, Photos, Chess…) are expected here."
        echo
        comm -23 "$WORK/installed.txt" "$WORK/managed.txt"
      } > "$MANIFESTS/orphan-apps.txt"
      N=$(comm -23 "$WORK/installed.txt" "$WORK/managed.txt" | wc -l | tr -d ' ')
      ok "manifests/orphan-apps.txt — $N unmanaged  ${DIM}← read this one${OFF}"
    else
      die "brew info --installed --json=v2 failed; skipped orphan detection"
    fi

    if command -v mas >/dev/null 2>&1; then
      mas list > "$MANIFESTS/mas-apps.txt" && ok "manifests/mas-apps.txt"
    else
      skip "mas not installed — 'brew install mas' to capture App Store purchases"
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 2. Fonts
# ------------------------------------------------------------------------------

if want fonts; then
  say "Fonts"
  {
    echo "# Fonts present at capture — $STAMP"
    echo "# Homebrew fonts are in the Brewfile; do NOT also restore them from the"
    echo "# tarball. Sign into Adobe CC and let it sync BEFORE restoring anything."
    echo
    echo "## ~/Library/Fonts"; ls -1 "$HOME/Library/Fonts" 2>/dev/null || echo "(none)"
    echo
    echo "## /Library/Fonts";  ls -1 "/Library/Fonts" 2>/dev/null || echo "(none)"
  } > "$MANIFESTS/fonts.txt"
  ok "manifests/fonts.txt — $(ls -1 "$HOME/Library/Fonts" 2>/dev/null | wc -l | tr -d ' ') user fonts"

  tar -czf "$ARCHIVE_ROOT/fonts-user.tar.gz" -C "$HOME/Library" Fonts \
    && ok "archive/fonts-user.tar.gz" || die "font tarball failed"
  tar -czf "$ARCHIVE_ROOT/font-collections.tar.gz" -C "$HOME/Library" FontCollections 2>/dev/null \
    && ok "archive/font-collections.tar.gz (Font Book collections)" || skip "no FontCollections"
fi

# ------------------------------------------------------------------------------
# 3. Obsidian
# ------------------------------------------------------------------------------

if want obsidian; then
  say "Obsidian"
  OBS_JSON="$HOME/Library/Application Support/obsidian/obsidian.json"
  if [ ! -f "$OBS_JSON" ]; then
    skip "obsidian.json not found at $OBS_JSON"
  else
    python3 -c "
import json
for v in json.load(open('$OBS_JSON')).get('vaults',{}).values():
    p = v.get('path')
    if p: print(p)
" > "$WORK/vaults.txt" 2>/dev/null

    if [ ! -s "$WORK/vaults.txt" ]; then
      die "could not read a vault list out of obsidian.json"
    else
      echo "# Obsidian state — $STAMP" > "$MANIFESTS/obsidian.md"
      while IFS= read -r VAULT; do
        [ -d "$VAULT" ] || { skip "missing vault: $VAULT"; continue; }
        NAME="$(basename "$VAULT")"
        SLUG="$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-')"
        O="$VAULT/.obsidian"
        {
          echo; echo "## $NAME"; echo "\`$VAULT\`"; echo
          echo "### Community plugins — installed"
          ls -1 "$O/plugins" 2>/dev/null | sed 's/^/- /' || echo "(none)"
          echo; echo "### Community plugins — enabled"
          python3 -c "
import json;print('\n'.join('- '+p for p in json.load(open('$O/community-plugins.json'))))
" 2>/dev/null || echo "(none)"
          echo; echo "### Core plugins — enabled"
          python3 -c "
import json
d = json.load(open('$O/core-plugins.json'))
it = d.items() if isinstance(d, dict) else ((k, True) for k in d)
print('\n'.join('- '+k for k, v in it if v))
" 2>/dev/null || echo "(unknown)"
          echo; echo "### Themes"
          ls -1 "$O/themes" 2>/dev/null | sed 's/^/- /' || echo "(default only)"
          echo; echo "### CSS snippets"
          ls -1 "$O/snippets" 2>/dev/null | sed 's/^/- /' || echo "(none)"
        } >> "$MANIFESTS/obsidian.md"

        tar -czf "$ARCHIVE_ROOT/obsidian-$SLUG-config.tar.gz" -C "$VAULT" \
          --exclude='.obsidian/workspace.json' \
          --exclude='.obsidian/workspace-mobile.json' \
          .obsidian 2>/dev/null && ok "archive/obsidian-$SLUG-config.tar.gz"

        tar -czf "$ARCHIVE_ROOT/obsidian-$SLUG-full.tar.gz" \
          -C "$(dirname "$VAULT")" --exclude='.trash' --exclude='.DS_Store' "$NAME" 2>/dev/null \
          && ok "archive/obsidian-$SLUG-full.tar.gz ($(du -sh "$VAULT" 2>/dev/null | cut -f1))"
      done < "$WORK/vaults.txt"
      ok "manifests/obsidian.md"
    fi
  fi
fi

# ------------------------------------------------------------------------------
# 4. Evernote
# ------------------------------------------------------------------------------

if want evernote; then
  say "Evernote"
  FOUND=0
  for D in "$HOME/Library/Application Support/Evernote" \
           "$HOME/Library/Containers/com.evernote.Evernote/Data/Library/Application Support/Evernote"; do
    [ -d "$D" ] || continue
    FOUND=1
    tar -czf "$ARCHIVE_ROOT/evernote-local-db.tar.gz" -C "$(dirname "$D")" "$(basename "$D")" 2>/dev/null \
      && ok "archive/evernote-local-db.tar.gz ($(du -sh "$D" 2>/dev/null | cut -f1))"
    break
  done
  [ $FOUND -eq 0 ] && skip "no local Evernote data found"
  mkdir -p "$ARCHIVE_ROOT/evernote-enex"
  warn ".enex export is MANUAL and desktop-only. Put the files in:"
  warn "  $ARCHIVE_ROOT/evernote-enex/"
fi

# ------------------------------------------------------------------------------
# 5. Browsers
# ------------------------------------------------------------------------------

if want browsers || want chrome; then
  say "Browsers"
  mkdir -p "$ARCHIVE_ROOT/chrome"
  N=0
  for ROOT in "$HOME/Library/Application Support/Google/Chrome" \
              "$HOME/Library/Application Support/Dia" \
              "$HOME/Library/Application Support/Comet" \
              "$HOME/Library/Application Support/BraveSoftware/Brave-Browser"; do
    [ -d "$ROOT" ] || continue
    B="$(basename "$ROOT")"
    while IFS= read -r BM; do
      P="$(basename "$(dirname "$BM")")"
      cp "$BM" "$ARCHIVE_ROOT/chrome/Bookmarks-${B// /_}-${P// /_}.json" \
        && { ok "archive/chrome/Bookmarks-$B-$P.json"; N=$((N+1)); }
    done < <(find "$ROOT" -maxdepth 2 -name Bookmarks -not -path '*/Snapshots/*' 2>/dev/null)
  done
  [ $N -eq 0 ] && skip "no Chromium bookmark files found"
  cp "$HOME/Library/Safari/Bookmarks.plist" "$ARCHIVE_ROOT/safari-bookmarks.plist" 2>/dev/null \
    && ok "archive/safari-bookmarks.plist" \
    || skip "Safari bookmarks need Full Disk Access for your terminal"
fi

# ------------------------------------------------------------------------------
# 6. Dotfiles, VS Code, defaults, creative, models, secrets
# ------------------------------------------------------------------------------

if want dotfiles; then
  say "Dotfiles"
  mkdir -p "$CONFIG/shell"
  for F in .zshrc .zprofile .zshenv .p10k.zsh .gitconfig .gitignore_global .editorconfig; do
    [ -f "$HOME/$F" ] && cp "$HOME/$F" "$CONFIG/shell/$F" && ok "config/shell/$F"
  done
  # OpenLogi keeps its whole config in one plain-text file — grab it if present
  if [ -f "$HOME/.config/openlogi/config.toml" ]; then
    mkdir -p "$CONFIG/openlogi"
    cp "$HOME/.config/openlogi/config.toml" "$CONFIG/openlogi/config.toml"
    ok "config/openlogi/config.toml"
  fi
  warn "Read config/shell/.gitconfig before committing — tokens hide in there"
fi

if want vscode; then
  say "VS Code"
  if command -v code >/dev/null 2>&1; then
    code --list-extensions > "$MANIFESTS/vscode-extensions.txt"
    ok "manifests/vscode-extensions.txt ($(wc -l < "$MANIFESTS/vscode-extensions.txt" | tr -d ' '))"
  else
    skip "'code' not on PATH — Cmd+Shift+P → 'Shell Command: Install code command'"
  fi
  VSC="$HOME/Library/Application Support/Code/User"
  if [ -d "$VSC" ]; then
    mkdir -p "$CONFIG/vscode"
    for F in settings.json keybindings.json; do
      [ -f "$VSC/$F" ] && cp "$VSC/$F" "$CONFIG/vscode/$F" && ok "config/vscode/$F"
    done
    [ -d "$VSC/snippets" ] && cp -R "$VSC/snippets" "$CONFIG/vscode/" && ok "config/vscode/snippets"
  fi
fi

if want defaults; then
  say "macOS defaults"
  mkdir -p "$ARCHIVE_ROOT/defaults"
  for D in com.apple.dock com.apple.finder com.apple.screencapture \
           com.apple.desktopservices com.apple.Safari NSGlobalDomain; do
    defaults export "$D" - > "$ARCHIVE_ROOT/defaults/$D.plist" 2>/dev/null && ok "defaults/$D.plist"
  done
  warn "Reference only. Hand-pick the ones you meant into install/10-defaults.sh."
fi

if want creative; then
  say "Creative app state"
  mkdir -p "$ARCHIVE_ROOT/creative"
  for PAIR in \
    "$HOME/Library/Application Support/Adobe/Lightroom:lightroom-settings" \
    "$HOME/Library/Application Support/Adobe/CameraRaw:camera-raw"; do
    SRC="${PAIR%:*}"; OUT="${PAIR##*:}"
    [ -d "$SRC" ] && tar -czf "$ARCHIVE_ROOT/creative/$OUT.tar.gz" \
      -C "$(dirname "$SRC")" "$(basename "$SRC")" 2>/dev/null \
      && ok "archive/creative/$OUT.tar.gz"
  done
  find "$HOME/Pictures" -maxdepth 3 -name '*.lrcat' 2>/dev/null > "$MANIFESTS/lightroom-catalogs.txt"
  if [ -s "$MANIFESTS/lightroom-catalogs.txt" ]; then
    ok "manifests/lightroom-catalogs.txt"
    warn "Catalogs are large — Optimize Catalog, quit Lr, then copy separately"
  fi
fi

if want models; then
  say "Local AI models (inventory only)"
  {
    echo "# Model inventory — $STAMP"
    echo "# Too big to archive. Relocate to the NAS and repoint the apps instead."
    echo
    for D in "$HOME/.cache/lm-studio/models" "$HOME/.lmstudio/models" \
             "$HOME/Library/Application Support/StabilityMatrix" \
             "$HOME/Documents/StabilityMatrix" "$HOME/StabilityMatrix"; do
      [ -d "$D" ] || continue
      echo "## $D  ($(du -sh "$D" 2>/dev/null | cut -f1))"
      find "$D" -maxdepth 5 \( -name '*.safetensors' -o -name '*.gguf' -o -name '*.ckpt' \) \
        -exec ls -lh {} \; 2>/dev/null | awk '{print "- "$NF"  ("$5")"}'
      echo
    done
  } > "$MANIFESTS/models.md"
  ok "manifests/models.md"
fi

if want secrets; then
  say "Secrets (inventory only — nothing archived)"
  {
    echo "# Secret material on this machine — $STAMP"
    echo "# Nothing here is auto-archived. Rotate rather than migrate."
    echo
    echo "## ~/.ssh"; ls -1 "$HOME/.ssh" 2>/dev/null | sed 's/^/- /' || echo "(none)"
    echo
    echo "## GPG"
    gpg --list-secret-keys --keyid-format=long 2>/dev/null | grep '^sec' | sed 's/^/- /' || echo "(none)"
    echo
    echo "## CLI credentials"
    for D in .aws .config/gh .config/gcloud .kube .npmrc .netrc; do
      [ -e "$HOME/$D" ] && echo "- ~/$D"
    done
  } > "$ARCHIVE_ROOT/SECRETS-INVENTORY.md"
  chmod 600 "$ARCHIVE_ROOT/SECRETS-INVENTORY.md"
  ok "archive/SECRETS-INVENTORY.md (0600)"
  warn "Preferred: generate new SSH keys post-wipe. A wipe is free key rotation."
fi

# ------------------------------------------------------------------------------

say "Sealing"
{
  echo "# mac-restore archive"; echo
  echo "- Captured: $(date)"
  echo "- Host: $(scutil --get ComputerName 2>/dev/null || hostname)"
  echo "- macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  echo "- CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
  MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  echo "- RAM: $(( MEM / 1073741824 )) GB"
  echo "- Repo: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo n/a)"
  echo; echo "## Contents"; echo
  ( cd "$ARCHIVE_ROOT" && find . -type f ! -name MANIFEST.md ! -name SHA256SUMS \
      -exec ls -lh {} \; | awk '{print "- "$NF"  ("$5")"}' | sort )
} > "$ARCHIVE_ROOT/MANIFEST.md"
( cd "$ARCHIVE_ROOT" && find . -type f ! -name SHA256SUMS -exec shasum -a 256 {} \; > SHA256SUMS )
ok "MANIFEST.md + SHA256SUMS"

printf "\n  repo     %s  %s(git add manifests brewfiles config)%s\n" "$REPO_ROOT" "$DIM" "$OFF"
printf "  archive  %s  (%s)\n\n" "$ARCHIVE_ROOT" "$(du -sh "$ARCHIVE_ROOT" 2>/dev/null | cut -f1)"
