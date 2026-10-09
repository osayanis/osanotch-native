#!/bin/bash
# Build + empaquetage .app + signature ad-hoc + (re)lancement.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
echo "▶︎ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/OsaNotch"

APP="OsaNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OsaNotch"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OsaNotch</string>
  <key>CFBundleDisplayName</key><string>OsaNotch</string>
  <key>CFBundleIdentifier</key><string>com.osalabs.osanotch</string>
  <key>CFBundleExecutable</key><string>OsaNotch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>OsaNotch lit et pilote Music/Spotify pour afficher la musique en cours.</string>
  <key>NSCalendarsUsageDescription</key><string>OsaNotch affiche votre prochain évènement.</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>OsaNotch affiche votre prochain évènement.</string>
  <key>NSLocalNetworkUsageDescription</key><string>OsaDrop transfère vos fichiers en P2P sur le réseau local.</string>
  <key>NSBonjourServices</key>
  <array><string>_osadrop._tcp</string><string>_osadrop._udp</string></array>
  <key>NSHumanReadableCopyright</key><string>OsaLabs</string>
    <key>NSCameraUsageDescription</key>
    <string>OsaNotch utilise la caméra pour la fonction miroir.</string>
</dict>
</plist>
PLIST

echo "▶︎ signature avec certificat développeur (évite les redemandes de permissions)…"
codesign --force --deep --sign "Apple Development: yanisb03@icloud.com (Q7R38U82N7)" "$APP" 2>/dev/null || true

echo "✅ $APP prêt."
