#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/sift-build"
SCHEME="Sift"
BUNDLE_ID="com.aporiac.sift"
TEAM_ID="1021415065"

echo "🔨 Building Sift for TestFlight..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
echo "📦 Creating archive..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -project "$PROJECT_DIR/Sift.xcodeproj" \
  -archivePath "$BUILD_DIR/Sift.xcarchive" \
  -configuration Release \
  -allowProvisioningUpdates

# Export
echo "📱 Exporting to .ipa..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/Sift.xcarchive" \
  -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR/Export" \
  -allowProvisioningUpdates

IPA_PATH="$BUILD_DIR/Export/Sift.ipa"

if [ ! -f "$IPA_PATH" ]; then
  echo "❌ IPA export failed"
  exit 1
fi

echo "✅ IPA ready: $IPA_PATH"
echo "📤 Uploading to TestFlight..."

# Upload using Transporter
xcrun altool --upload-app \
  --file "$IPA_PATH" \
  --type ios \
  --username "$APPLE_ID" \
  --password "@keychain:AC_PASSWORD" 2>&1 | grep -E "(Successfully|Error|warning)"

echo "✅ Upload complete! Check TestFlight in ~5-15 minutes"
