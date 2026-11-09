#!/usr/bin/env bash
#
# find-casks.sh — work out which orphan apps actually have a Homebrew cask.
#
#   ./find-casks.sh                              # read ../manifests/orphan-apps.txt
#   ./find-casks.sh "Roon" "TIDAL" "Sleeve"      # check specific names
#   ./find-casks.sh --write                      # also emit brewfiles/Brewfile.candidates
#
# For each app name: guess a slug, ask brew if that cask exists, and if not,
# fall back to a fuzzy search. Prints a three-column report:
#
#   EXACT   the slug resolves — safe to put in a Brewfile
#   FUZZY   brew found something close — eyeball it before trusting it
#   NONE    no cask. App Store (mas), manual download, or drop it.
#
# Nothing is installed. This only reads.

if [ -z "${BASH_VERSION:-}" ]; then exec /usr/bin/env bash "$0" "$@"; fi
set -uo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; DIM=$'\033[2m'; OFF=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# NOTE: `A || B && C` parses as `(A || B) && C` in sh. Resolving this inline
# silently returned the wrong directory. Keep it as explicit branches.
if REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)"; then
  :
elif [ -d "$SCRIPT_DIR/../manifests" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/manifests" ]; then
  REPO_ROOT="$SCRIPT_DIR"
else
  REPO_ROOT="$PWD"
fi

WRITE=0
ORPHANS=""
NAMES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --write)   WRITE=1 ;;
    --orphans) shift; ORPHANS="$1" ;;
    -h|--help) sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        echo "unknown flag: $1" >&2; exit 2 ;;
    *)         NAMES+=("$1") ;;
  esac
  shift
done

[ -n "$ORPHANS" ] || ORPHANS="$REPO_ROOT/manifests/orphan-apps.txt"

# If the default path is missing, look where capture.sh plausibly wrote it
if [ ! -f "$ORPHANS" ]; then
  for TRY in "$PWD/manifests/orphan-apps.txt" \
             "$SCRIPT_DIR/manifests/orphan-apps.txt" \
             "$HOME/Downloads/manifests/orphan-apps.txt"; do
    [ -f "$TRY" ] && { ORPHANS="$TRY"; break; }
  done
fi

command -v brew >/dev/null 2>&1 || { echo "brew not on PATH" >&2; exit 1; }

# Apps that will never have a cask, and shouldn't be reported as failures.
IGNORE='^(Safari|Utilities|Mail|Photos|Chess|Contacts|Calendar|Notes|Reminders|Messages|FaceTime|Music|TV|Podcasts|News|Stocks|Weather|Maps|Home|Freeform|Journal|Preview|QuickTime Player|TextEdit|Terminal|Automator|Shortcuts|Siri|Clock|Calculator|Dictionary|Font Book|Image Capture|Photo Booth|Time Machine|Mission Control|System Settings|App Store|Books|Find My|Games|Apps|Tips|Voice Memos|Stickies|Passwords|Image Playground|iPhone Mirroring|Adobe (Acrobat|Bridge|Illustrator|InDesign|Lightroom|Photoshop)|Microsoft (Excel|Word|PowerPoint|Outlook|OneNote|Teams|Defender))'

if [ ${#NAMES[@]} -eq 0 ]; then
  if [ ! -f "$ORPHANS" ]; then
    echo "Can't find orphan-apps.txt." >&2
    echo "  looked in: $REPO_ROOT/manifests/" >&2
    echo "  point at it directly:  $0 --orphans /path/to/orphan-apps.txt --write" >&2
    echo "  or find it:            find ~ -name orphan-apps.txt -maxdepth 4 2>/dev/null" >&2
    exit 1
  fi
  echo "  reading $ORPHANS"
  while IFS= read -r L; do
    case "$L" in ''|'#'*) continue ;; esac
    echo "$L" | grep -qE "$IGNORE" && continue
    NAMES+=("$L")
  done < "$ORPHANS"
fi

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/\.app$//' -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

# Apps already coming from the Mac App Store are handled by `mas` lines in the
# Brewfile — don't recommend a cask that would install a second copy.
MAS_NAMES=""
if [ -f "$REPO_ROOT/manifests/mas-apps.txt" ]; then
  MAS_NAMES="$(sed -E 's/^ *[0-9]+ +//; s/ +\(.*\)$//' "$REPO_ROOT/manifests/mas-apps.txt" | sed 's/ *$//')"
elif [ -f "$(dirname "$ORPHANS")/mas-apps.txt" ]; then
  MAS_NAMES="$(sed -E 's/^ *[0-9]+ +//; s/ +\(.*\)$//' "$(dirname "$ORPHANS")/mas-apps.txt" | sed 's/ *$//')"
fi

EXACT=(); FUZZY=(); NONE=(); FROM_MAS=()

printf "\nChecking %s app%s against Homebrew…\n\n" "${#NAMES[@]}" "$([ ${#NAMES[@]} -eq 1 ] || echo s)"

for APP in "${NAMES[@]}"; do
  if [ -n "$MAS_NAMES" ] && printf '%s\n' "$MAS_NAMES" | grep -qxF "$APP"; then
    printf "  ${BLUE}MAS${OFF}    %-26s → App Store (mas)\n" "$APP"
    FROM_MAS+=("$APP")
    continue
  fi
  SLUG="$(slugify "$APP")"
  # Try a few obvious variants before giving up
  HIT=""
  for CAND in "$SLUG" "${SLUG%-desktop}" "${SLUG%-gui}" "${SLUG//-/}"; do
    [ -n "$CAND" ] || continue
    if brew info --cask "$CAND" >/dev/null 2>&1; then HIT="$CAND"; break; fi
  done

  if [ -n "$HIT" ]; then
    printf "  ${GREEN}EXACT${OFF}  %-26s → %s\n" "$APP" "$HIT"
    EXACT+=("$HIT|$APP")
    continue
  fi

  # Fuzzy: search on the first word, which is usually the distinctive one
  FIRST="$(echo "$SLUG" | cut -d- -f1)"
  MATCHES="$(brew search --cask "$FIRST" 2>/dev/null | grep -v '^==>' | tr -d ' ' | grep -v '^$' | head -4 | paste -sd, -)"
  if [ -n "$MATCHES" ]; then
    printf "  ${YELLOW}FUZZY${OFF}  %-26s ? %s\n" "$APP" "$MATCHES"
    FUZZY+=("$APP|$MATCHES")
  else
    printf "  ${DIM}NONE${OFF}   %-26s   ${DIM}mas / manual / drop${OFF}\n" "$APP"
    NONE+=("$APP")
  fi
done

printf "\n  ${GREEN}%s exact${OFF} · ${YELLOW}%s fuzzy${OFF} · ${BLUE}%s app store${OFF} · %s none\n\n" \
  "${#EXACT[@]}" "${#FUZZY[@]}" "${#FROM_MAS[@]}" "${#NONE[@]}"

if [ "$WRITE" -eq 1 ] && [ ${#EXACT[@]} -gt 0 ]; then
  OUT="$REPO_ROOT/brewfiles/Brewfile.candidates"
  mkdir -p "$(dirname "$OUT")"
  {
    echo "# Candidates resolved by tools/find-casks.sh on $(date +%F)"
    echo "# Every line below is a cask that exists. Sort them into the tiered"
    echo "# Brewfiles by hand — existing is not the same as wanted."
    echo
    for E in "${EXACT[@]}"; do
      printf 'cask "%s" # %s\n' "${E%%|*}" "${E##*|}"
    done
    if [ ${#FUZZY[@]} -gt 0 ]; then
      echo; echo "# --- needs a human decision ---"
      for F in "${FUZZY[@]}"; do printf '# %-26s candidates: %s\n' "${F%%|*}" "${F##*|}"; done
    fi
    if [ ${#FROM_MAS[@]} -gt 0 ]; then
      echo; echo "# --- already from the App Store: keep the mas lines instead ---"
      for M in "${FROM_MAS[@]}"; do printf '# %s\n' "$M"; done
    fi
    if [ ${#NONE[@]} -gt 0 ]; then
      echo; echo "# --- no cask: mas entry, manual download, or drop ---"
      for N in "${NONE[@]}"; do printf '# %s\n' "$N"; done
    fi
  } > "$OUT"
  echo "  wrote $OUT"
  echo
fi
