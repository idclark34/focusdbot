#!/bin/bash

# This is a .command file that can be double-clicked in Finder
cd "$(dirname "$0")"

echo "🤖 Installing FocusdBot Simple..."
echo ""

# Check if FocusdBot-Simple.app exists
if [ ! -d "FocusdBot-Simple.app" ]; then
    echo "❌ FocusdBot-Simple.app not found!"
    echo "Make sure you extracted all files from the ZIP."
    read -p "Press Enter to exit..."
    exit 1
fi

# Remove quarantine attributes
echo "🔓 Removing security restrictions..."
xattr -cr FocusdBot-Simple.app

# Copy to Applications
echo "📦 Copying to Applications folder..."
rm -rf "/Applications/FocusdBot-Simple.app"
cp -R FocusdBot-Simple.app "/Applications/"

# Fix permissions
chmod +x "/Applications/FocusdBot-Simple.app/Contents/MacOS/FocusdBot-Simple"

echo ""
echo "✅ Installation complete!"
echo ""
echo "🚀 To launch FocusdBot Simple:"
echo "• Press Cmd+Space and type 'FocusdBot Simple'"
echo "• Or check your Applications folder"
echo "• Look for the robot 🤖 in your menu bar!"
echo ""
echo "📝 This is the SIMPLE version without AI features:"
echo "• No activity tracking"
echo "• No AI summaries"
echo "• Just pure focus timing"
echo "• Faster and lighter!"
echo ""
echo "If you get a security warning:"
echo "• Go to System Preferences > Security & Privacy"
echo "• Click 'Open Anyway' for FocusdBot Simple"
echo ""
read -p "Press Enter to exit..."
