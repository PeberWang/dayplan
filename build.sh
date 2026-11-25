#!/bin/zsh
# 开发用：编译并装到 ~/Applications/DayPlan.app。真正的编译与安装逻辑在 scripts/install.sh，
# 自动更新也走那一份，避免两条路径行为不一致。
set -e
cd "${0:A:h}"
exec ./scripts/install.sh
