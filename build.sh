#!/bin/bash
# Builds STICKWARS.app (release) and signs it ad hoc with a pinned designated requirement,
# so macOS keeps the Screen Recording / Accessibility grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/STICKWARS"

APP=STICKWARS.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/STICKWARS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.galawaydude.stickwars</string>
    <key>CFBundleName</key><string>STICKWARS</string>
    <key>CFBundleDisplayName</key><string>STICKWARS</string>
    <key>CFBundleExecutable</key><string>STICKWARS</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>STICKWARS freezes your screen into a level to play on. Nothing is saved or sent anywhere.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.galawaydude.stickwars \
    -r='designated => identifier "com.galawaydude.stickwars"' "$APP"
echo "Built $APP"
