#!/bin/bash

# FocusdBot DMG Creation Script
# This creates a beautiful disk image for easy distribution

APP_NAME="FocusdBot"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}"
APP_PATH="dist/${APP_NAME}.app"
DMG_DIR="dmg-temp"
DMG_PATH="dist/${DMG_NAME}.dmg"

echo "🤖 Creating DMG for ${APP_NAME} v${VERSION}..."

# Clean up any existing DMG directory
rm -rf "${DMG_DIR}"
rm -f "${DMG_PATH}"

# Create temporary DMG directory
mkdir -p "${DMG_DIR}"

# Copy the app bundle
echo "📦 Copying app bundle..."
cp -R "${APP_PATH}" "${DMG_DIR}/"

# Create Applications symlink for easy installation
echo "🔗 Creating Applications symlink..."
ln -s /Applications "${DMG_DIR}/Applications"

# Create a README file
cat > "${DMG_DIR}/README.txt" << EOF
FocusdBot - Your AI Focus Companion
===================================

Thank you for downloading FocusdBot! 🤖

INSTALLATION:
1. Drag FocusdBot.app to the Applications folder
2. Open FocusdBot from Applications or Spotlight
3. Grant necessary permissions when prompted
4. Enjoy focused productivity!

FEATURES:
• Adorable robot companion in your menu bar
• Smart distraction detection
• Beautiful productivity analytics
• Pomodoro timer with reflection prompts
• iPhone integration for complete focus tracking
• Multiple timer display styles

REQUIREMENTS:
• macOS 13 (Ventura) or later
• Accessibility permissions (for app tracking)
• AppleScript permissions (for Safari integration)

SUPPORT:
Visit our website for documentation and support.

Happy focusing! 🚀
EOF

# Calculate size for DMG (add some padding)
SIZE=$(du -sm "${DMG_DIR}" | cut -f1)
SIZE=$((SIZE + 10))

echo "📏 DMG size: ${SIZE}MB"

# Create the DMG
echo "💿 Creating disk image..."
hdiutil create -srcfolder "${DMG_DIR}" -volname "${APP_NAME}" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size ${SIZE}m "temp-${DMG_NAME}.dmg"

# Mount the DMG to customize it
echo "🎨 Mounting and customizing DMG..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "temp-${DMG_NAME}.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/${APP_NAME}"

# Wait for mount
sleep 2

# Set custom icon positions and view options
osascript << EOF
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 920, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 72
        set background picture of viewOptions to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {130, 220}
        set position of item "Applications" of container window to {390, 220}
        set position of item "README.txt" of container window to {260, 350}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Unmount the DMG
echo "📤 Unmounting DMG..."
hdiutil detach "${DEVICE}"

# Convert to final compressed DMG
echo "🗜️  Compressing final DMG..."
hdiutil convert "temp-${DMG_NAME}.dmg" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"

# Clean up
rm -f "temp-${DMG_NAME}.dmg"
rm -rf "${DMG_DIR}"

echo "✅ DMG created successfully: ${DMG_PATH}"
echo "📊 Final size: $(du -h "${DMG_PATH}" | cut -f1)"
echo ""
echo "🚀 Your FocusdBot installer is ready for distribution!"