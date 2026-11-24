#!/bin/zsh
# Build DayPlan and install it to ~/Applications.
set -e
cd "${0:A:h}/.."

echo "Building..."
swiftc -O -parse-as-library -o DayPlan DayPlanApp.swift

APP="$HOME/Applications/DayPlan.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp DayPlan "$APP/Contents/MacOS/DayPlan"
cp Info.plist "$APP/Contents/Info.plist"
if [ -f assets/AppIcon.icns ]; then
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Installed: $APP"
echo "Open it with: open -a DayPlan"
