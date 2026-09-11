#!/bin/sh
# Builds ActiveWindow.app in ./dist from the Swift package.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=dist/ActiveWindow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ActiveWindow "$APP/Contents/MacOS/ActiveWindow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ActiveWindow</string>
    <key>CFBundleIdentifier</key><string>com.nick318.ActiveWindow</string>
    <key>CFBundleName</key><string>ActiveWindow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Prefer a stable Developer ID identity so macOS keeps the Accessibility permission across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
IDENTITY="${IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened runtime and a secure timestamp are required for notarization.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Signed with: $IDENTITY"
echo "Built $APP"
