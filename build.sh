#!/bin/bash
# Builds a universal Voca.app, zips it to dist/, and installs it to /Applications (skip with NO_INSTALL=1).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Voca"
APP=.build/Voca.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# macOS ties Accessibility/Microphone grants to the designated requirement. An ad-hoc signature's default
# requirement is the code hash, which changes every build; pinning it to the bundle ID keeps grants across updates.
codesign --force --sign "${SIGN_ID:--}" -r='designated => identifier "co.yellowmetal.voca"' "$APP"

mkdir -p dist
rm -f dist/Voca-macOS.zip
ditto -c -k --keepParent "$APP" dist/Voca-macOS.zip
echo "Built dist/Voca-macOS.zip"

[ "${NO_INSTALL:-}" = 1 ] && exit 0
pkill -x Voca || true
rm -rf /Applications/Voca.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Voca.app
echo "Installed /Applications/Voca.app"
