#!/bin/sh
# 编译并把 DayPlan 装到 ~/Applications/DayPlan.app。
#
# 自动更新（设置里的「自动检查并更新」）也跑这个脚本：先编译到临时文件，
# 成功后才替换已安装的二进制。任何一步失败都保留旧版本、退出码非零，
# 由应用把错误写进 ~/Library/Logs/DayPlan-update.log。
#
# 最后把仓库绝对路径写进 UserDefaults 的 installRepo —— 应用靠它判断这是
# git 安装，并知道往哪个目录 fetch / pull。
set -eu

SRC=$(cd "$(dirname "$0")/.." && pwd)
cd "$SRC"

# 从 Finder 启动时 PATH 很短，补齐 Swift 与系统工具的常见位置。
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

BUNDLE_ID="io.github.peberwang.dayplan"
APP="$HOME/Applications/DayPlan.app"
OUT="$SRC/.build"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc not found; install Command Line Tools (xcode-select --install)" >&2
  exit 1
fi

mkdir -p "$OUT"

# 1. 编译到临时文件：失败不会碰到已安装的二进制
swiftc -O -parse-as-library -o "$OUT/DayPlan.new" DayPlanApp.swift

# 2. 组装 .app（已存在就原地更新内容）
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

ICON=""
if [ -f Resources/AppIcon.icns ]; then
  ICON=Resources/AppIcon.icns
elif [ -f assets/AppIcon.icns ]; then
  ICON=assets/AppIcon.icns
fi
if [ -n "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

# 3. 原子替换二进制：先放到新文件名再 mv，正在跑的旧进程不受影响
cp "$OUT/DayPlan.new" "$APP/Contents/MacOS/DayPlan.new"
chmod +x "$APP/Contents/MacOS/DayPlan.new"
mv -f "$APP/Contents/MacOS/DayPlan.new" "$APP/Contents/MacOS/DayPlan"

# 4. ad-hoc 签名
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

# 5. 记下安装来源，供应用里的自动更新使用
defaults write "$BUNDLE_ID" installRepo -string "$SRC"

rm -f "$OUT/DayPlan.new"
echo "installed $APP from $SRC"
