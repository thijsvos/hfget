#!/bin/sh
# hfget installer — copies the hfget script onto your PATH.
#
#   curl -fsSL https://raw.githubusercontent.com/thijsvos/hfget/main/install.sh | sh
#
# Or, from a clone:  ./install.sh
#
# Honors DESTDIR to override the target directory:
#   curl -fsSL .../install.sh | DESTDIR=~/bin sh
set -eu

REPO="thijsvos/hfget"
RAW="https://raw.githubusercontent.com/$REPO/main/hfget"

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }

# Pick a destination: explicit DESTDIR > a writable /usr/local/bin > ~/.local/bin
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
  echo "Downloading hfget → $DEST/hfget ..."
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
