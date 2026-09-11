#!/bin/sh
# Builds dist/ActiveWindow.dmg: a drag-and-drop installer with the app and an Applications shortcut.
set -e
cd "$(dirname "$0")"

./build-app.sh

NAME=ActiveWindow
APP=dist/$NAME.app
DMG=dist/$NAME.dmg
STAGE=dist/dmg-stage
RW=dist/$NAME-rw.dmg

# Notarization credentials. Either an App Store Connect API key:
#   NOTARY_KEY_PATH   path to AuthKey_XXXXXXXXXX.p8 (default: first key in ~/.private_keys)
#   NOTARY_KEY_ID     key id (default: derived from the file name)
#   NOTARY_ISSUER_ID  issuer id from App Store Connect > Users and Access > Integrations
# or a keychain profile saved with `xcrun notarytool store-credentials`:
#   NOTARY_PROFILE    profile name
# Set NOTARIZE=0 to skip notarization.
NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-$(ls "$HOME"/.private_keys/AuthKey_*.p8 2>/dev/null | head -1)}"
if [ -z "${NOTARY_KEY_ID:-}" ] && [ -n "$NOTARY_KEY_PATH" ]; then
    NOTARY_KEY_ID=$(basename "$NOTARY_KEY_PATH" .p8 | sed 's/^AuthKey_//')
fi

notary_args() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
    else
        printf '%s\n' --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    fi
}

can_notarize() {
    [ "${NOTARIZE:-1}" != "0" ] || return 1
    [ -n "${NOTARY_PROFILE:-}" ] && return 0
    [ -n "$NOTARY_KEY_PATH" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]
}

# Submits a file, waits for the verdict, prints the log on failure, staples the ticket.
notarize() {
    target=$1
    echo "notarizing $target"
    out=$(xcrun notarytool submit "$target" $(notary_args) --wait 2>&1) || true
    echo "$out"
    id=$(echo "$out" | sed -n 's/^ *id: //p' | head -1)
    status=$(echo "$out" | sed -n 's/^ *status: //p' | tail -1)
    case "$status" in
        Accepted) ;;
        *)
            [ -n "$id" ] && xcrun notarytool log "$id" $(notary_args) || true
            echo "notarization failed for $target" >&2
            exit 1
            ;;
    esac
}

if can_notarize; then
    ditto -c -k --keepParent "$APP" dist/notarize.zip
    notarize dist/notarize.zip
    rm -f dist/notarize.zip
    # A ticket cannot be stapled to a zip; staple the app bundle itself.
    xcrun stapler staple "$APP"
else
    echo "skipping notarization (no credentials; see comments in make-dmg.sh)" >&2
fi

rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Writable image first, so Finder can store the icon layout in it.
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -nobrowse "$RW" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 740, 520}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 14
        set position of item "$NAME.app" of container window to {140, 150}
        set position of item "Applications" of container window to {400, 150}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "$MOUNT"

# Compressed read-only image for distribution.
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$RW" "$STAGE"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    echo "Signed DMG with: $IDENTITY"
fi

if can_notarize; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG"
fi

echo "Built $DMG"
