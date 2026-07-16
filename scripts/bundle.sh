#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Pasture"
BUNDLE_ID="com.sevecod.pasture"
VERSION="1.9.0"
BUILD_DIR="$PROJECT_DIR/.build/release"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

echo "Building $APP_NAME v$VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BUILD_DIR/pasture-mcp" "$APP_BUNDLE/Contents/MacOS/pasture-mcp"

if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "Icon copied."
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 SeveCod. All rights reserved.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.sevecod.pasture</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pasture</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>New Pasture Capture</string>
            </dict>
            <key>NSMessage</key>
            <string>capturePasture</string>
            <key>NSPortName</key>
            <string>Pasture</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# v1.9 — firma ad-hoc: reduce la fricción de Gatekeeper y estabiliza permisos
# TCC (notificaciones). El binario anidado pasture-mcp se firma primero.
echo "Signing (ad-hoc)..."
codesign --force -s - "$APP_BUNDLE/Contents/MacOS/pasture-mcp"
codesign --force -s - "$APP_BUNDLE"
codesign --verify --deep "$APP_BUNDLE" && echo "Signature OK."

echo "Creating zip..."
cd "$OUTPUT_DIR"
zip -r -y "$APP_NAME-v$VERSION-macOS.zip" "$APP_NAME.app"

echo ""
echo "Done!"
echo "  App:  $APP_BUNDLE"
echo "  Zip:  $OUTPUT_DIR/$APP_NAME-v$VERSION-macOS.zip"
echo ""
echo "To install: unzip and drag $APP_NAME.app to /Applications"
