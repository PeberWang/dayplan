#!/bin/zsh
# 编译并装到 ~/Applications/DayPlan.app（保留 Info.plist 与图标）
set -e
cd "${0:A:h}"
swiftc -O -parse-as-library -o DayPlan DayPlanApp.swift
APP=~/Applications/DayPlan.app
cp DayPlan "$APP/Contents/MacOS/DayPlan"
if [ -f Info.plist ]; then
  cp Info.plist "$APP/Contents/Info.plist"
fi
codesign --force --deep --sign - "$APP"
echo "built + installed: $APP"
