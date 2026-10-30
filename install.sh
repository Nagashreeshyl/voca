#!/bin/bash
# Voca installer: curl -fsSL https://raw.githubusercontent.com/Nagashreeshyl/voca/main/install.sh | bash
set -euo pipefail
REPO="Nagashreeshyl/voca"

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
  echo "Voca needs macOS 26 (Tahoe) or newer. You have $(sw_vers -productVersion)." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "→ Downloading the latest Voca…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/Voca-macOS.zip" -o "$TMP/Voca.zip"
ditto -x -k "$TMP/Voca.zip" "$TMP"

echo "→ Installing to /Applications…"
pkill -x Voca 2>/dev/null || true
rm -rf /Applications/Voca.app
mv "$TMP/Voca.app" /Applications/
# The app isn't notarized by Apple, so clear the download flag that would make Gatekeeper block it.
xattr -dr com.apple.quarantine /Applications/Voca.app 2>/dev/null || true

open /Applications/Voca.app
cat <<'MSG'

✓ Voca is installed and running (look for the waveform in your menu bar).

Next:
  1. Paste your free Groq key in the window that opened (console.groq.com/keys).
  2. Allow Microphone and Accessibility when macOS asks, then quit and reopen Voca.
  3. System Settings → Keyboard → "Press 🌐 key to" → Do Nothing.
  4. Hold Fn and talk.
MSG
