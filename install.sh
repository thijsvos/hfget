#!/bin/sh
# hfget installer — installs the hfget script into a bin dir and tells you how
# to put that dir on your PATH. Uses ./hfget from a clone when present,
# otherwise downloads the latest tagged release (falling back to main).
#
#   curl -fsSL https://raw.githubusercontent.com/thijsvos/hfget/main/install.sh | sh
#
# Or, from a clone:  ./install.sh
#
# Honors DESTDIR to override the target directory:
#   curl -fsSL .../install.sh | DESTDIR=~/bin sh
# Without it: /usr/local/bin when writable, else ~/.local/bin (never sudo).
# POSIX sh; requires curl. Notes when 'jq' (needed by hfget itself) is missing.
set -eu

REPO="thijsvos/hfget"

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

# Resolve the latest tagged release for the download below; fall back to main
# when there is none or we are offline. A local ./hfget wins regardless.
TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep '"tag_name"' | head -n 1 | sed -E 's/.*"tag_name" *: *"([^"]+)".*/\1/')
REF="${TAG:-main}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/hfget"

# Destination: explicit DESTDIR > a writable /usr/local/bin > ~/.local/bin
if [ -n "${DESTDIR:-}" ]; then
  DEST="$DESTDIR"
elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
  DEST="/usr/local/bin"
else
  DEST="$HOME/.local/bin"
fi
mkdir -p "$DEST"

# Install from a local clone if present, else download from the repo.
if [ -f "$(dirname "$0")/hfget" ]; then
  cp "$(dirname "$0")/hfget" "$DEST/hfget"
  echo "Installed hfget from local copy → $DEST/hfget"
else
  echo "Downloading hfget ($REF) → $DEST/hfget ..."
  curl -fSL "$RAW" -o "$DEST/hfget"
fi
chmod +x "$DEST/hfget"

command -v jq >/dev/null 2>&1 || \
  echo "note: hfget also needs 'jq' — install it with apt/dnf/brew."

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "Add $DEST to your PATH:  export PATH=\"$DEST:\$PATH\"" ;;
esac

echo "Done. Try:  hfget --help"
