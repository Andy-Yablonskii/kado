#!/bin/sh
# Archives the personal build (branch `andy`) and uploads it to TestFlight.
# Usage (from the repo root): Scripts/ship-andy.sh
#
# Same shape as Andy-Book's tools/ship-ios.sh: the App Store Connect API key
# signs and uploads, the build number is a timestamp, and the internal
# TestFlight group "Andy" gets every build automatically.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Key ID, issuer and tester id live outside the repo (the fork is public).
ENV_FILE="$HOME/.appstoreconnect/kado.env"
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE (ASC_KEY_ID, ASC_ISSUER_ID, ASC_TESTER_ID)"; exit 1; }
set -a; . "$ENV_FILE"; set +a
API_KEY_ID=$ASC_KEY_ID
API_ISSUER_ID=$ASC_ISSUER_ID
API_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_$API_KEY_ID.p8"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
BUILD_DIR="$ROOT/build/andy"
ARCHIVE_PATH="$BUILD_DIR/Kado.xcarchive"
AUTH="-allowProvisioningUpdates -authenticationKeyPath $API_KEY_PATH -authenticationKeyID $API_KEY_ID -authenticationKeyIssuerID $API_ISSUER_ID"

[ -f "$API_KEY_PATH" ] || { echo "Missing App Store Connect key: $API_KEY_PATH"; exit 1; }
cd "$ROOT"
# Fails fast, with the fix, when the App Store Connect app doesn't exist yet.
python3 Scripts/ensure-andy-testflight.py
make deployment-check

rm -rf "$ARCHIVE_PATH"
mkdir -p "$BUILD_DIR"
# shellcheck disable=SC2086
xcodebuild -project Kado.xcodeproj -scheme Kado -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" $AUTH archive > "$BUILD_DIR/archive.log" 2>&1 || true
grep -E "error:|ARCHIVE" "$BUILD_DIR/archive.log" || true
[ -d "$ARCHIVE_PATH" ] || { echo "Archive failed - see build/andy/archive.log"; exit 1; }

cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>34JXV2N65F</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/export" $AUTH > "$BUILD_DIR/export.log" 2>&1 || true
grep -E "error:|EXPORT|Upload" "$BUILD_DIR/export.log" || true
grep -q "EXPORT SUCCEEDED" "$BUILD_DIR/export.log" || { echo "Upload FAILED - see build/andy/export.log"; exit 1; }
python3 Scripts/ensure-andy-testflight.py >/dev/null
echo "Build $BUILD_NUMBER sent to TestFlight. It shows up in the TestFlight app once Apple finishes processing (usually 5-15 min)."
