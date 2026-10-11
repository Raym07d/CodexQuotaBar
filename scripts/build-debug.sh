#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c debug
APP="$PWD/build/Debug/CodexQuotaBar.app"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c debug --show-bin-path)/CodexQuotaBar" "$APP/Contents/MacOS/CodexQuotaBar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexQuotaBar</string>
<key>CFBundleIdentifier</key><string>local.dr.CodexQuotaBar</string>
<key>CFBundleName</key><string>CodexQuotaBar</string>
<key>CFBundleDisplayName</key><string>Codex Quota</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Debug app: $APP"
