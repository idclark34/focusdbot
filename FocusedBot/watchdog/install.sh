#!/bin/bash

echo "🤖 FocusdBot Installer"
echo "====================="
echo ""

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ This installer only works on macOS"
    exit 1
fi

# Check macOS version
MACOS_VERSION=$(sw_vers -productVersion)
REQUIRED_VERSION="13.0"

if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$MACOS_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
    echo "❌ macOS 13.0 (Ventura) or later required. You have $MACOS_VERSION"
    exit 1
fi

echo "✅ macOS $MACOS_VERSION detected"
echo ""

# Build the app
echo "🔨 Building FocusdBot..."
if ! swift build --target FocusdBot -c debug; then
    echo "❌ Build failed"
    exit 1
fi

# Create app bundle
echo "📦 Creating app bundle..."
mkdir -p dist/FocusdBot.app/Contents/{MacOS,Resources}

# Copy executable
cp .build/arm64-apple-macosx/debug/FocusdBot dist/FocusdBot.app/Contents/MacOS/

# Create Info.plist
cat > dist/FocusdBot.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>FocusdBot</string>
    <key>CFBundleExecutable</key>
    <string>FocusdBot</string>
    <key>CFBundleIdentifier</key>
    <string>com.focusdbot.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FocusdBot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>FocusdBot needs to access Safari to detect website visits for focus tracking.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
EOF

# Create placeholder icon
touch dist/FocusdBot.app/Contents/Resources/AppIcon.icns

# Install to Applications
echo "🚀 Installing to Applications..."
rm -rf /Applications/FocusdBot.app
cp -R dist/FocusdBot.app /Applications/

# Remove quarantine attribute
xattr -d com.apple.quarantine /Applications/FocusdBot.app 2>/dev/null || true

echo ""
echo "✅ Installation complete!"
echo ""
echo "🎯 To launch FocusdBot:"
echo "1. Go to Applications folder"
echo "2. Double-click FocusdBot.app"
echo "3. Look for the robot in your menu bar!"
echo ""
echo "🤖 Enjoy your new focus companion!"