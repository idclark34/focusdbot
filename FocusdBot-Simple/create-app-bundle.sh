#!/bin/bash

# Build the app first
echo "Building FocusdBot Simple..."
swift build -c release

# Create app bundle structure
APP_NAME="FocusdBot-Simple"
BUNDLE_DIR="dist/${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Creating app bundle structure..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy the executable
echo "Copying executable..."
cp ".build/release/FocusdBot" "${MACOS_DIR}/${APP_NAME}"

# Create Info.plist
echo "Creating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusdbot.simple</string>
    <key>CFBundleName</key>
    <string>FocusdBot Simple</string>
    <key>CFBundleDisplayName</key>
    <string>FocusdBot Simple</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Make executable
chmod +x "${MACOS_DIR}/${APP_NAME}"

echo "✅ App bundle created at: ${BUNDLE_DIR}"
echo "📦 Size: $(du -sh "${BUNDLE_DIR}" | cut -f1)"

# Create ZIP for distribution
echo "Creating ZIP for distribution..."
cd dist
zip -r "${APP_NAME}-1.0.0.zip" "${APP_NAME}.app"
cd ..

echo "✅ Distribution ZIP created: dist/${APP_NAME}-1.0.0.zip"
echo "📦 ZIP Size: $(du -sh "dist/${APP_NAME}-1.0.0.zip" | cut -f1)"
